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

    func testCanvasFillPathColorShadingEmitsScenePath() async {
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
            XCTAssertEqual(scene.layers[0].paths.count, 1)
            let path = scene.layers[0].paths[0]
            XCTAssertEqual(path.fillColor.red, 0)
            XCTAssertEqual(path.fillColor.green, 1)
            XCTAssertEqual(path.fillColor.blue, 0)
            XCTAssertEqual(path.fillColor.alpha, 1)
        }
    }

    func testCanvasStrokePathColorShadingProducesStrokedScenePath() async {
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
            XCTAssertEqual(scene.layers[0].paths.count, 1)
            let path = scene.layers[0].paths[0]
            XCTAssertEqual(path.strokeColor.blue, 1)
            XCTAssertEqual(path.lineWidth, 3)
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
            // Translation degenerates fillRect into a transformed-corner path
            // primitive (axis-aligned but emitted via the path API).
            XCTAssertEqual(scene.layers[0].paths.count, 1)
            let path = scene.layers[0].paths[0]
            XCTAssertEqual(path.bounds.minX, 25)
            XCTAssertEqual(path.bounds.minY, 15)
            XCTAssertEqual(path.bounds.width, 40)
            XCTAssertEqual(path.bounds.height, 20)
            XCTAssertEqual(path.fillColor.red, 1)
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
            XCTAssertEqual(scene.layers[0].paths.count, 1)
            let path = scene.layers[0].paths[0]
            XCTAssertEqual(path.bounds.width, 40)
            XCTAssertEqual(path.bounds.height, 20)
        }
    }

    func testCanvasRotateProducesRotatedPathBounds() async {
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
            XCTAssertEqual(scene.layers[0].paths.count, 1)
            let path = scene.layers[0].paths[0]
            // 90° rotation swaps width/height of the original 20x10 rect.
            XCTAssertEqual(path.bounds.width, 10, accuracy: 0.001)
            XCTAssertEqual(path.bounds.height, 20, accuracy: 0.001)
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
            // Sub-context fill is a translated-corner path; outer fill stays
            // a quad because the parent's transform stayed identity.
            XCTAssertEqual(scene.layers[0].paths.count, 1)
            let path = scene.layers[0].paths[0]
            XCTAssertEqual(path.bounds.minX, 50)
            XCTAssertEqual(path.bounds.minY, 30)
            XCTAssertEqual(path.fillColor.green, 1)

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
            XCTAssertEqual(scene.layers[0].paths.count, 1)
            let path = scene.layers[0].paths[0]
            // Sub-context inherited parent's translation, so the path lands
            // at (20, 10).
            XCTAssertEqual(path.bounds.minX, 20)
            XCTAssertEqual(path.bounds.minY, 10)
            XCTAssertEqual(path.fillColor.blue, 1)
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
