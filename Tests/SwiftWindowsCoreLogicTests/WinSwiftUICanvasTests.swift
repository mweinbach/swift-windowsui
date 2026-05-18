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
                    with: .linearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
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
                    with: .linearGradient(gradient: gradient, startPoint: .top, endPoint: .bottom)
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
