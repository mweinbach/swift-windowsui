import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class WinSwiftUICanvasTests: XCTestCase {

    private func snapshot<V: View>(
        _ view: V,
        size: IntSize = IntSize(width: 120, height: 80)
    ) -> GPUIScene {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: view,
            size: size,
            displayScale: 1,
            clearColor: .black
        ).scene
    }

    // MARK: - Shading.color

    func testCanvasFillRectColorShadingEmitsScenePrimitive() async {
        await MainActor.run {
            let view = Canvas { ctx, size in
                ctx.fill(
                    Rect(x: 10, y: 5, width: 40, height: 20),
                    with: .color(Color(red: 1, green: 0, blue: 0, alpha: 1))
                )
                _ = size
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            let canvasQuads = scene.layers[0].quads.filter {
                $0.width == 40 && $0.height == 20
            }
            XCTAssertEqual(canvasQuads.count, 1, "Expected one canvas-emitted quad")
            XCTAssertEqual(canvasQuads[0].startR, 1)
            XCTAssertEqual(canvasQuads[0].startG, 0)
            XCTAssertEqual(canvasQuads[0].startB, 0)
            XCTAssertEqual(canvasQuads[0].startA, 1)
        }
    }

    func testCanvasFillPathColorShadingEmitsSceneQuadForAxisAlignedRect() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                var path = Path()
                path.moveTo(Point(x: 5, y: 5))
                path.lineTo(Point(x: 35, y: 5))
                path.lineTo(Point(x: 35, y: 35))
                path.lineTo(Point(x: 5, y: 35))
                path.close()
                ctx.fill(path, with: .color(Color(red: 0, green: 1, blue: 0, alpha: 1)))
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            // An axis-aligned rectangle path now short-circuits to a
            // GPU quad via PathToQuadTessellator — no CPU-rasterized
            // PathPrimitive emitted.
            XCTAssertEqual(scene.layers[0].paths.count, 0)
            let greenQuads = scene.layers[0].quads.filter {
                $0.width == 30 && $0.height == 30 && $0.startG == 1
            }
            XCTAssertEqual(greenQuads.count, 1)
            XCTAssertEqual(greenQuads[0].startR, 0)
            XCTAssertEqual(greenQuads[0].startB, 0)
            XCTAssertEqual(greenQuads[0].startA, 1)
        }
    }

    func testCanvasStrokePathColorShadingProducesGPUQuadForAxisAlignedSegment() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                var path = Path()
                path.moveTo(Point(x: 10, y: 10))
                path.lineTo(Point(x: 80, y: 10))
                ctx.stroke(
                    path,
                    with: .color(Color(red: 0, green: 0, blue: 1, alpha: 1)),
                    lineWidth: 3
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            // A purely horizontal stroked line now bypasses CPU
            // rasterization via PathToQuadTessellator. The emitted
            // quad covers the segment plus half-lineWidth on each end.
            XCTAssertEqual(scene.layers[0].paths.count, 0)
            let blueQuads = scene.layers[0].quads.filter {
                $0.startB == 1 && $0.startR == 0 && $0.startG == 0
            }
            XCTAssertEqual(blueQuads.count, 1)
            XCTAssertEqual(blueQuads[0].height, 3, accuracy: 0.001)
            // x = min(10,80) - lineWidth/2 = 8.5, width = 70 + 3 = 73
            XCTAssertEqual(Double(blueQuads[0].x), 8.5, accuracy: 0.001)
            XCTAssertEqual(Double(blueQuads[0].width), 73, accuracy: 0.001)
        }
    }

    // MARK: - Shading.linearGradient

    func testCanvasFillRectGradientShadingPropagatesEndpointsThroughAxis() async {
        await MainActor.run {
            let gradient = Gradient(colors: [
                Color(red: 0.20, green: 0.30, blue: 0.40, alpha: 1),
                Color(red: 0.80, green: 0.90, blue: 0.10, alpha: 1),
            ])
            let view = Canvas { ctx, _ in
                ctx.fill(
                    Rect(x: 0, y: 0, width: 50, height: 30),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: 15),
                        endPoint: CGPoint(x: 50, y: 15)
                    )
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            let quads = scene.layers[0].quads.filter {
                $0.width == 50 && $0.height == 30
            }
            XCTAssertEqual(quads.count, 1)
            let quad = quads[0]
            // Horizontal axis (.leading -> .trailing) encodes gradientAxis == 1.
            XCTAssertEqual(quad.gradientAxis, 1)
            XCTAssertEqual(quad.startR, 0.20, accuracy: 0.001)
            XCTAssertEqual(quad.endR, 0.80, accuracy: 0.001)
            XCTAssertEqual(quad.endG, 0.90, accuracy: 0.001)
        }
    }

    func testCanvasFillRectVerticalGradientEncodesVerticalAxis() async {
        await MainActor.run {
            let gradient = Gradient(colors: [
                Color(red: 0.10, green: 0.20, blue: 0.30, alpha: 1),
                Color(red: 0.70, green: 0.40, blue: 0.10, alpha: 1),
            ])
            let view = Canvas { ctx, _ in
                ctx.fill(
                    Rect(x: 0, y: 0, width: 40, height: 60),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 20, y: 0),
                        endPoint: CGPoint(x: 20, y: 60)
                    )
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            let quads = scene.layers[0].quads.filter {
                $0.width == 40 && $0.height == 60
            }
            XCTAssertEqual(quads.count, 1)
            XCTAssertEqual(quads[0].gradientAxis, 0)  // vertical
        }
    }

    // MARK: - Opacity

    func testCanvasOpacityMultipliesIntoSubsequentColorFills() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                ctx.opacity = 0.5
                ctx.fill(
                    Rect(x: 0, y: 0, width: 40, height: 20),
                    with: .color(Color(red: 1, green: 0, blue: 0, alpha: 1))
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            let quads = scene.layers[0].quads.filter {
                $0.width == 40 && $0.height == 20
            }
            XCTAssertEqual(quads.count, 1)
            XCTAssertEqual(quads[0].startA, 0.5, accuracy: 0.001)
        }
    }

    func testCanvasOpacityAppliesPerOperation() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                ctx.opacity = 0.25
                ctx.fill(
                    Rect(x: 0, y: 0, width: 30, height: 30),
                    with: .color(Color(red: 1, green: 0, blue: 0, alpha: 1))
                )
                ctx.opacity = 1.0
                ctx.fill(
                    Rect(x: 40, y: 0, width: 30, height: 30),
                    with: .color(Color(red: 0, green: 0, blue: 1, alpha: 1))
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            let quads = scene.layers[0].quads.filter {
                $0.width == 30 && $0.height == 30
            }.sorted { $0.x < $1.x }
            XCTAssertEqual(quads.count, 2)
            XCTAssertEqual(quads[0].startR, 1)
            XCTAssertEqual(quads[0].startA, 0.25, accuracy: 0.001)
            XCTAssertEqual(quads[1].startB, 1)
            XCTAssertEqual(quads[1].startA, 1.0, accuracy: 0.001)
        }
    }

    func testCanvasOpacityFoldsIntoGradientStops() async {
        await MainActor.run {
            let gradient = Gradient(colors: [
                Color(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
                Color(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
            ])
            let view = Canvas { ctx, _ in
                ctx.opacity = 0.5
                ctx.fill(
                    Rect(x: 0, y: 0, width: 40, height: 20),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: 10),
                        endPoint: CGPoint(x: 40, y: 10)
                    )
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            let quads = scene.layers[0].quads.filter {
                $0.width == 40 && $0.height == 20
            }
            XCTAssertEqual(quads.count, 1)
            XCTAssertEqual(quads[0].startA, 0.5, accuracy: 0.001)
            XCTAssertEqual(quads[0].endA, 0.5, accuracy: 0.001)
        }
    }

    // MARK: - Transform

    func testCanvasIdentityTransformKeepsRectAxisAligned() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                ctx.fill(
                    Rect(x: 0, y: 0, width: 40, height: 20),
                    with: .color(Color(red: 1, green: 0, blue: 0, alpha: 1))
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            // No transform applied: identity path stays a fillRect (quad), no
            // PathPrimitive emitted.
            let quads = scene.layers[0].quads.filter {
                $0.width == 40 && $0.height == 20
            }
            XCTAssertEqual(quads.count, 1)
            XCTAssertEqual(scene.layers[0].paths.count, 0)
        }
    }

    func testCanvasTranslateByOffsetsSubsequentFill() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                ctx.translateBy(x: 25, y: 15)
                ctx.fill(
                    Rect(x: 0, y: 0, width: 40, height: 20),
                    with: .color(Color(red: 1, green: 0, blue: 0, alpha: 1))
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            // Translated rect-fill is axis-aligned, so PathToQuadTessellator
            // promotes it to a GPU quad rather than a PathPrimitive.
            XCTAssertEqual(scene.layers[0].paths.count, 0)
            let redQuads = scene.layers[0].quads.filter { $0.startR == 1 && $0.startG == 0 }
            XCTAssertEqual(redQuads.count, 1)
            XCTAssertEqual(Double(redQuads[0].x), 25, accuracy: 0.001)
            XCTAssertEqual(Double(redQuads[0].y), 15, accuracy: 0.001)
            XCTAssertEqual(Double(redQuads[0].width), 40, accuracy: 0.001)
            XCTAssertEqual(Double(redQuads[0].height), 20, accuracy: 0.001)
        }
    }

    func testCanvasScaleByEnlargesSubsequentFill() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                ctx.scaleBy(x: 2, y: 2)
                ctx.fill(
                    Rect(x: 0, y: 0, width: 20, height: 10),
                    with: .color(Color(red: 0, green: 1, blue: 0, alpha: 1))
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            // Scaled rect-fill stays axis-aligned, promoted to a quad.
            XCTAssertEqual(scene.layers[0].paths.count, 0)
            let greenQuads = scene.layers[0].quads.filter { $0.startG == 1 && $0.startR == 0 }
            XCTAssertEqual(greenQuads.count, 1)
            XCTAssertEqual(Double(greenQuads[0].width), 40, accuracy: 0.001)
            XCTAssertEqual(Double(greenQuads[0].height), 20, accuracy: 0.001)
        }
    }

    func testCanvasRotateProducesRotatedQuadBounds() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                ctx.translateBy(x: 60, y: 40)
                ctx.rotate(by: .degrees(90))
                ctx.fill(
                    Rect(x: -10, y: -5, width: 20, height: 10),
                    with: .color(Color(red: 0, green: 0, blue: 1, alpha: 1))
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            // 90° rotation of an axis-aligned rect is still axis-aligned,
            // so PathToQuadTessellator promotes it to a quad. Dimensions
            // swap: 20×10 → 10×20.
            XCTAssertEqual(scene.layers[0].paths.count, 0)
            let blueQuads = scene.layers[0].quads.filter { $0.startB == 1 && $0.startR == 0 }
            XCTAssertEqual(blueQuads.count, 1)
            XCTAssertEqual(blueQuads[0].width, 10, accuracy: 0.001)
            XCTAssertEqual(blueQuads[0].height, 20, accuracy: 0.001)
        }
    }

    func testCanvasTranslateByOffsetsPathFill() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                ctx.translateBy(x: 30, y: 20)
                var path = Path()
                path.moveTo(Point(x: 0, y: 0))
                path.lineTo(Point(x: 10, y: 0))
                path.lineTo(Point(x: 10, y: 10))
                path.close()
                ctx.fill(path, with: .color(Color(red: 1, green: 1, blue: 0, alpha: 1)))
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            XCTAssertEqual(scene.layers[0].paths.count, 1)
            let primitive = scene.layers[0].paths[0]
            XCTAssertEqual(primitive.bounds.minX, 30)
            XCTAssertEqual(primitive.bounds.minY, 20)
            XCTAssertEqual(primitive.bounds.width, 10)
            XCTAssertEqual(primitive.bounds.height, 10)
        }
    }

    // MARK: - Color.gradient

    func testColorGradientProducesVerticalAnyGradient() async {
        await MainActor.run {
            let base = Color(red: 0.50, green: 0.30, blue: 0.70, alpha: 1)
            let anyGradient = base.gradient
            let linear = anyGradient.retainedLinearGradient

            // SwiftUI's Color.gradient is a top-bright / bottom-dim vertical
            // sweep.  Verify both endpoints are derived from the base color
            // and that the start is lighter than the end.
            XCTAssertTrue(linear.startColor.red > base.red)
            XCTAssertTrue(linear.endColor.red < base.red)
            XCTAssertEqual(linear.axis, .vertical)
        }
    }

    func testColorGradientShapeStyleConformanceProducesLinearForegroundStyle() async {
        await MainActor.run {
            let base = Color(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
            let foreground = base.gradient.retainedForegroundStyle
            switch foreground {
            case .linearGradient(let gradient):
                XCTAssertEqual(gradient.axis, .vertical)
            default:
                XCTFail("Color.gradient should resolve to a linearGradient foreground style")
            }
        }
    }

    // MARK: - Gradient stops

    func testGradientInitWithStopsPreservesCustomLocations() async {
        await MainActor.run {
            let gradient = Gradient(stops: [
                Gradient.Stop(color: Color(red: 1, green: 0, blue: 0, alpha: 1), location: 0),
                Gradient.Stop(color: Color(red: 0, green: 1, blue: 0, alpha: 1), location: 0.25),
                Gradient.Stop(color: Color(red: 0, green: 0, blue: 1, alpha: 1), location: 1),
            ])

            let recovered = gradient.swiftUIStops
            XCTAssertEqual(recovered.count, 3)
            XCTAssertEqual(recovered[0].location, 0, accuracy: 0.001)
            XCTAssertEqual(recovered[1].location, 0.25, accuracy: 0.001)
            XCTAssertEqual(recovered[2].location, 1, accuracy: 0.001)

            // Same locations should be visible in the runtime-shaped stops too.
            let runtimeStops = gradient.stops
            XCTAssertEqual(Float(runtimeStops[1].position), 0.25, accuracy: 0.001)
        }
    }

    func testGradientInitWithColorsDistributesLocationsEvenly() async {
        await MainActor.run {
            let gradient = Gradient(colors: [.red, .green, .blue, .white])
            let stops = gradient.swiftUIStops
            XCTAssertEqual(stops.count, 4)
            XCTAssertEqual(stops[0].location, 0, accuracy: 0.001)
            XCTAssertEqual(stops[1].location, 1.0 / 3.0, accuracy: 0.001)
            XCTAssertEqual(stops[2].location, 2.0 / 3.0, accuracy: 0.001)
            XCTAssertEqual(stops[3].location, 1, accuracy: 0.001)
        }
    }

    // MARK: - drawLayer

    func testCanvasDrawLayerDoesNotLeakTransformBackToParent() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                ctx.drawLayer { sub in
                    sub.translateBy(x: 50, y: 30)
                    sub.fill(
                        Rect(x: 0, y: 0, width: 20, height: 20),
                        with: .color(Color(red: 0, green: 1, blue: 0, alpha: 1))
                    )
                }
                // Parent ctx.transform should still be identity here.
                ctx.fill(
                    Rect(x: 0, y: 0, width: 20, height: 20),
                    with: .color(Color(red: 1, green: 0, blue: 0, alpha: 1))
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            // Sub-context fill of an axis-aligned rect now goes through
            // PathToQuadTessellator's GPU fast path, producing a quad
            // instead of a CPU-rasterized PathPrimitive. The outer fill
            // also stays a quad because the parent's transform stayed
            // identity. Both fills now render purely on the GPU.
            XCTAssertEqual(scene.layers[0].paths.count, 0)
            let greenQuads = scene.layers[0].quads.filter {
                $0.width == 20 && $0.height == 20 && $0.startG == 1
            }
            XCTAssertEqual(greenQuads.count, 1)
            XCTAssertEqual(Double(greenQuads[0].x), 50, accuracy: 0.001)
            XCTAssertEqual(Double(greenQuads[0].y), 30, accuracy: 0.001)

            let outerQuads = scene.layers[0].quads.filter {
                $0.width == 20 && $0.height == 20 && $0.startR == 1
            }
            XCTAssertEqual(outerQuads.count, 1)
            XCTAssertEqual(outerQuads[0].x, 0)
            XCTAssertEqual(outerQuads[0].y, 0)
        }
    }

    func testCanvasDrawLayerInheritsParentTransform() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                ctx.translateBy(x: 20, y: 10)
                ctx.drawLayer { sub in
                    sub.fill(
                        Rect(x: 0, y: 0, width: 30, height: 30),
                        with: .color(Color(red: 0, green: 0, blue: 1, alpha: 1))
                    )
                }
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            // PathToQuadTessellator promotes the rect-fill to a quad even
            // when emitted via the path path (since the inherited translation
            // produced an axis-aligned rect at (20, 10)). Verify the quad
            // landed at the inherited offset.
            XCTAssertEqual(scene.layers[0].paths.count, 0)
            let blueQuads = scene.layers[0].quads.filter {
                $0.width == 30 && $0.height == 30 && $0.startB == 1
            }
            XCTAssertEqual(blueQuads.count, 1)
            XCTAssertEqual(Double(blueQuads[0].x), 20, accuracy: 0.001)
            XCTAssertEqual(Double(blueQuads[0].y), 10, accuracy: 0.001)
        }
    }

    func testCanvasDrawLayerOpacityDoesNotLeakOutward() async {
        await MainActor.run {
            let view = Canvas { ctx, _ in
                ctx.drawLayer { sub in
                    sub.opacity = 0.25
                    sub.fill(
                        Rect(x: 0, y: 0, width: 20, height: 20),
                        with: .color(Color(red: 1, green: 0, blue: 0, alpha: 1))
                    )
                }
                ctx.fill(
                    Rect(x: 30, y: 0, width: 20, height: 20),
                    with: .color(Color(red: 0, green: 0, blue: 1, alpha: 1))
                )
            }
            .frame(width: 120, height: 80)

            let scene = snapshot(view)
            // Inside the layer: red fill with alpha 0.25. Outside: blue at full
            // alpha, since the parent's opacity stayed at 1.0.
            let reds = scene.layers[0].quads.filter { $0.startR == 1 }
            XCTAssertEqual(reds.count, 1)
            XCTAssertEqual(reds[0].startA, 0.25, accuracy: 0.001)

            let blues = scene.layers[0].quads.filter { $0.startB == 1 }
            XCTAssertEqual(blues.count, 1)
            XCTAssertEqual(blues[0].startA, 1.0, accuracy: 0.001)
        }
    }

    // MARK: - Clip stack

    func testCanvasPushedClipNarrowsEmittedQuadClip() async {
        await MainActor.run {
            let view = Canvas { ctx, size in
                ctx.clip(to: Rect(x: 5, y: 5, width: 20, height: 20))
                ctx.fill(
                    Rect(x: 0, y: 0, width: size.width, height: size.height),
                    with: .color(Color(red: 1, green: 1, blue: 1, alpha: 1))
                )
                ctx.popClip()
            }
            .frame(width: 100, height: 100)

            let scene = snapshot(view, size: IntSize(width: 100, height: 100))
            let canvasFills = scene.layers[0].quads.filter {
                $0.startR == 1 && $0.startG == 1 && $0.startB == 1 && $0.startA == 1
            }
            XCTAssertEqual(canvasFills.count, 1)
            let quad = canvasFills[0]
            XCTAssertEqual(quad.clipX, 5)
            XCTAssertEqual(quad.clipY, 5)
            XCTAssertEqual(quad.clipWidth, 20)
            XCTAssertEqual(quad.clipHeight, 20)
        }
    }
}
