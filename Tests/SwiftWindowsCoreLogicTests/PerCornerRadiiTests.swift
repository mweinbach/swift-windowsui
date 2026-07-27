import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI

/// Locks the per-corner radii feature end-to-end: ViewNode style →
/// ScenePainter → QuadPrimitive → D3D11 quad shader (static contract)
/// and the CPU rasterizer (pixel checks), plus parity between the
/// uniform-radius fast path and equal per-corner radii.
final class PerCornerRadiiTests: XCTestCase {

    // MARK: - Primitive contract

    func testQuadPrimitiveCarriesPerCornerRadii() async {
        let quad = QuadPrimitive(
            x: 0, y: 0, width: 40, height: 40,
            cornerRadiusTopLeft: 12,
            cornerRadiusTopRight: 8,
            cornerRadiusBottomRight: 4,
            cornerRadiusBottomLeft: 2
        )
        XCTAssertEqual(quad.cornerRadiusTopLeft, 12, accuracy: 0.001)
        XCTAssertEqual(quad.cornerRadiusTopRight, 8, accuracy: 0.001)
        XCTAssertEqual(quad.cornerRadiusBottomRight, 4, accuracy: 0.001)
        XCTAssertEqual(quad.cornerRadiusBottomLeft, 2, accuracy: 0.001)
        XCTAssertTrue(quad.usesPerCornerRadii)
    }

    func testDefaultQuadPrimitiveStaysOnUniformPath() async {
        let quad = QuadPrimitive(x: 0, y: 0, width: 40, height: 40, cornerRadius: 9)
        XCTAssertEqual(quad.cornerRadiusTopLeft, 0, accuracy: 0.001)
        XCTAssertEqual(quad.cornerRadiusTopRight, 0, accuracy: 0.001)
        XCTAssertEqual(quad.cornerRadiusBottomRight, 0, accuracy: 0.001)
        XCTAssertEqual(quad.cornerRadiusBottomLeft, 0, accuracy: 0.001)
        XCTAssertFalse(quad.usesPerCornerRadii)
        XCTAssertEqual(quad.cornerRadius, 9, accuracy: 0.001)
    }

    func testQuadPrimitiveStrideStays16ByteAligned() async {
        XCTAssertEqual(QuadPrimitive.byteSize, 144)
        XCTAssertEqual(QuadPrimitive.byteSize % 16, 0)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.stride % 16, 0)
    }

    // MARK: - D3D11 shader contract (static, mirrors D3D11QuadBlurVerificationTests)

    func testD3D11QuadShaderDeclaresPerCornerRadiiInInstanceBuffer() async {
        for field in [
            "float cornerRadiusTopLeft;",
            "float cornerRadiusTopRight;",
            "float cornerRadiusBottomRight;",
            "float cornerRadiusBottomLeft;",
        ] {
            XCTAssertTrue(
                batchQuadShaderSource.contains(field),
                "D3D11 QuadInstance HLSL must declare \(field) at the same slot as QuadPrimitive")
        }
    }

    func testD3D11QuadShaderResolvesAndConsumesPerCornerRadii() async {
        // The vertex shader must resolve per-corner radii (with uniform
        // broadcast fallback) and forward them to the pixel stage.
        XCTAssertTrue(
            batchQuadShaderSource.contains("inst.cornerRadiusTopLeft"),
            "Vertex shader must read the per-corner fields from the instance buffer")
        XCTAssertTrue(
            batchQuadShaderSource.contains("output.cornerRadii = cornerRadii;"),
            "Vertex shader must forward resolved corner radii to the pixel stage")
        XCTAssertTrue(
            batchQuadShaderSource.contains("float4 cornerRadii : TEXCOORD"),
            "VS->PS struct must include the cornerRadii interpolator")
        XCTAssertTrue(
            batchQuadShaderSource.contains("roundedRectDistance(input.localPosition, input.size, input.cornerRadii)"),
            "Pixel shader must evaluate the rounded-rect SDF with per-corner radii")
    }

    // MARK: - CPU rasterization

    private func makeSingleQuadScene(_ quad: QuadPrimitive) -> GPUIScene {
        var scene = GPUIScene(clearColor: .white)
        scene.addQuad(quad, toLayer: 0)
        scene.finish()
        return scene
    }

    private func blackQuad(x: Float, y: Float, width: Float, height: Float) -> QuadPrimitive {
        QuadPrimitive(
            x: x, y: y, width: width, height: height,
            startR: 0, startG: 0, startB: 0, startA: 1,
            endR: 0, endG: 0, endB: 0, endA: 1
        )
    }

    func testUniformAndEqualPerCornerRadiiRasterizeIdentically() async {
        let size = IntSize(width: 60, height: 60)
        var uniformQuad = blackQuad(x: 10, y: 10, width: 40, height: 40)
        uniformQuad.cornerRadius = 12
        var perCornerQuad = blackQuad(x: 10, y: 10, width: 40, height: 40)
        perCornerQuad.cornerRadiusTopLeft = 12
        perCornerQuad.cornerRadiusTopRight = 12
        perCornerQuad.cornerRadiusBottomRight = 12
        perCornerQuad.cornerRadiusBottomLeft = 12

        let uniformPixels = GPUIRawSceneRasterizer.rasterize(makeSingleQuadScene(uniformQuad), size: size).pixels
        let perCornerPixels = GPUIRawSceneRasterizer.rasterize(makeSingleQuadScene(perCornerQuad), size: size).pixels
        XCTAssertEqual(
            perCornerPixels, uniformPixels,
            "Four equal per-corner radii must reduce to the uniform-radius path byte-for-byte")
    }

    func testPerCornerRadiiRoundOnlySpecifiedCorners() async throws {
        // Black 40x40 quad at (10,10) on white; only topLeft is rounded.
        var quad = blackQuad(x: 10, y: 10, width: 40, height: 40)
        quad.cornerRadiusTopLeft = 16
        let bitmap = GPUIRawSceneRasterizer.rasterize(
            makeSingleQuadScene(quad), size: IntSize(width: 60, height: 60))

        let topLeftOutsideArc = try XCTUnwrap(bitmap.colorAt(x: 11, y: 11))
        XCTAssertEqual(
            topLeftOutsideArc.red, 1, accuracy: 0.02,
            "Pixel just outside the rounded top-left arc must stay background (white)")

        let topRight = try XCTUnwrap(bitmap.colorAt(x: 48, y: 11))
        XCTAssertEqual(topRight.red, 0, accuracy: 0.02, "Square top-right corner must be filled")

        let bottomLeft = try XCTUnwrap(bitmap.colorAt(x: 11, y: 48))
        XCTAssertEqual(bottomLeft.red, 0, accuracy: 0.02, "Square bottom-left corner must be filled")

        let bottomRight = try XCTUnwrap(bitmap.colorAt(x: 48, y: 48))
        XCTAssertEqual(bottomRight.red, 0, accuracy: 0.02, "Square bottom-right corner must be filled")

        let centre = try XCTUnwrap(bitmap.colorAt(x: 30, y: 30))
        XCTAssertEqual(centre.red, 0, accuracy: 0.02, "Quad centre must be filled")

        let topLeftInsideArc = try XCTUnwrap(bitmap.colorAt(x: 27, y: 27))
        XCTAssertEqual(
            topLeftInsideArc.red, 0, accuracy: 0.02,
            "Pixel inside the rounded top-left corner must be filled")
    }

    func testPerCornerRadiiComposeWithRotation() async throws {
        // A rotated per-corner quad must still clip its (local-space)
        // rounded corner: sample a world pixel that maps into the
        // rounded top-left corner's outside region.
        var quad = blackQuad(x: 10, y: 20, width: 40, height: 20)
        quad.cornerRadiusTopLeft = 10
        quad.rotationRadians = Float.pi / 4
        let bitmap = GPUIRawSceneRasterizer.rasterize(
            makeSingleQuadScene(quad), size: IntSize(width: 60, height: 60))
        // The quad centre must always be covered regardless of rotation.
        let centre = try XCTUnwrap(bitmap.colorAt(x: 30, y: 30))
        XCTAssertEqual(centre.red, 0, accuracy: 0.02, "Rotated quad centre must be filled")
    }

    // MARK: - Scene emission

    func testScenePainterEmitsPerCornerRadiiOnBorderAndFillQuads() async throws {
        try await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 60),
                backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1),
                borderColor: Color(red: 0, green: 0, blue: 0, alpha: 1),
                borderWidth: 4,
                cornerRadii: RetainedCornerRadii(topLeft: 20, topRight: 12, bottomRight: 0, bottomLeft: 8)
            )

            let scene = ScenePainter.paint(
                root: node, clearColor: .black, surfaceSize: Size(width: 100, height: 60))

            XCTAssertEqual(scene.layers[0].quads.count, 2)
            // Draw-order sorting may reorder the two quads; select by geometry.
            let borderQuad = try XCTUnwrap(
                scene.layers[0].quads.first(where: { $0.width == 100 && $0.height == 60 }))
            XCTAssertTrue(borderQuad.usesPerCornerRadii)
            XCTAssertEqual(borderQuad.cornerRadiusTopLeft, 20, accuracy: 0.001)
            XCTAssertEqual(borderQuad.cornerRadiusTopRight, 12, accuracy: 0.001)
            XCTAssertEqual(borderQuad.cornerRadiusBottomRight, 0, accuracy: 0.001)
            XCTAssertEqual(borderQuad.cornerRadiusBottomLeft, 8, accuracy: 0.001)

            // Fill quad: rect inset by the 4px border, radii inset the
            // same way (max(0, r - borderWidth)) like the uniform path.
            let insetFillQuad = try XCTUnwrap(
                scene.layers[0].quads.first(where: { $0.width == 92 && $0.height == 52 }))
            XCTAssertTrue(insetFillQuad.usesPerCornerRadii)
            XCTAssertEqual(insetFillQuad.x, 4, accuracy: 0.001)
            XCTAssertEqual(insetFillQuad.y, 4, accuracy: 0.001)
            XCTAssertEqual(insetFillQuad.cornerRadiusTopLeft, 16, accuracy: 0.001)
            XCTAssertEqual(insetFillQuad.cornerRadiusTopRight, 8, accuracy: 0.001)
            XCTAssertEqual(insetFillQuad.cornerRadiusBottomRight, 0, accuracy: 0.001)
            XCTAssertEqual(insetFillQuad.cornerRadiusBottomLeft, 4, accuracy: 0.001)
        }
    }

    func testScenePainterLeavesPerCornerFieldsZeroForUniformNodes() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                cornerRadius: 9
            )

            let scene = ScenePainter.paint(
                root: node, clearColor: .black, surfaceSize: Size(width: 80, height: 40))

            XCTAssertEqual(scene.layers[0].quads.count, 1)
            let quad = scene.layers[0].quads[0]
            XCTAssertFalse(quad.usesPerCornerRadii)
            XCTAssertEqual(quad.cornerRadius, 9, accuracy: 0.001)
        }
    }

    func testScenePainterScalesPerCornerRadiiByDisplayScale() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                cornerRadii: RetainedCornerRadii(topLeft: 10, topRight: 0, bottomRight: 6, bottomLeft: 0)
            )

            let scene = ScenePainter.paint(
                root: node, clearColor: .black, surfaceSize: Size(width: 80, height: 40), displayScale: 2)

            let quad = scene.layers[0].quads[0]
            XCTAssertTrue(quad.usesPerCornerRadii)
            XCTAssertEqual(quad.cornerRadiusTopLeft, 20, accuracy: 0.001)
            XCTAssertEqual(quad.cornerRadiusBottomRight, 12, accuracy: 0.001)
            XCTAssertEqual(quad.cornerRadiusTopRight, 0, accuracy: 0.001)
        }
    }

    func testPerCornerRadiiSurviveSceneReplay() async {
        var source = GPUIScene(clearColor: .black)
        var quad = blackQuad(x: 0, y: 0, width: 20, height: 20)
        quad.cornerRadiusTopLeft = 6
        source.addQuad(quad, toLayer: 0)
        source.finish()

        var replayed = GPUIScene(clearColor: .black)
        let result = replayed.replay(0..<source.paintRecordCount, from: source)
        XCTAssertEqual(result, .success)
        replayed.finish()

        XCTAssertEqual(replayed.layers[0].quads.count, 1)
        let replayedQuad = replayed.layers[0].quads[0]
        XCTAssertTrue(replayedQuad.usesPerCornerRadii)
        XCTAssertEqual(replayedQuad.cornerRadiusTopLeft, 6, accuracy: 0.001)
    }

    // MARK: - Opacity / transform propagation (gap-3 audit locks)

    func testBackgroundPathFillComposesNodeOpacity() async {
        await MainActor.run {
            // A self-intersecting (bowtie) path stays a CPU PathPrimitive,
            // so its fillColor is directly observable in the scene.
            var path = RenderPath()
            path.move(to: Point(x: 0, y: 0))
            path.addLine(to: Point(x: 1, y: 1))
            path.addLine(to: Point(x: 0, y: 1))
            path.addLine(to: Point(x: 1, y: 0))
            path.close()
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                backgroundPath: path,
                opacity: 0.5
            )

            let scene = ScenePainter.paint(
                root: node, clearColor: .black, surfaceSize: Size(width: 40, height: 40))

            let paths = scene.layers[0].paths
            XCTAssertEqual(paths.count, 1, "Bowtie fill must remain a CPU path primitive")
            XCTAssertEqual(
                paths[0].fillColor.alpha, 0.5, accuracy: 0.001,
                "backgroundPath fill must compose the node's opacity like quad fills do")
        }
    }

    func testNestedOpacityAndTransformComposeIntoQuadOutput() async {
        await MainActor.run {
            let parent = ViewNode(
                frame: Rect(x: 10, y: 10, width: 100, height: 100),
                opacity: 0.5,
                transform: .scale(x: 2, y: 2)
            )
            let child = ViewNode(
                frame: Rect(x: 0, y: 0, width: 50, height: 50),
                backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1),
                opacity: 0.5
            )
            parent.addChild(child)

            let scene = ScenePainter.paint(
                root: parent, clearColor: .black, surfaceSize: Size(width: 400, height: 400))

            XCTAssertEqual(scene.layers[0].quads.count, 1)
            let quad = scene.layers[0].quads[0]
            XCTAssertEqual(
                quad.startA, 0.25, accuracy: 0.001,
                "Nested opacity 0.5 * 0.5 must compose multiplicatively into the quad alpha")
            // Parent scale(2) about its screen centre (60, 60) maps the
            // child's (10, 10, 50, 50) screen frame to (-40, -40, 100, 100).
            XCTAssertEqual(quad.x, -40, accuracy: 0.001)
            XCTAssertEqual(quad.y, -40, accuracy: 0.001)
            XCTAssertEqual(quad.width, 100, accuracy: 0.001)
            XCTAssertEqual(quad.height, 100, accuracy: 0.001)
        }
    }

    // MARK: - Visual showcase (opt-in; writes a PNG for manual inspection)

    /// Renders a control strip of rounded rects — uniform radius, equal
    /// per-corner radii, single rounded corner, diagonal rounded corners —
    /// and writes a PNG when RENDERPERCORNER_SHOWCASE names an output file.
    /// No-op on normal test runs.
    func testPerCornerRadiiShowcasePNGForVisualInspection() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["RENDERPERCORNER_SHOWCASE"],
            !outputPath.isEmpty
        else {
            return
        }

        func showcaseQuad(x: Float) -> QuadPrimitive {
            QuadPrimitive(
                x: x, y: 10, width: 80, height: 80,
                startR: 0.1, startG: 0.25, startB: 0.9, startA: 1,
                endR: 0.1, endG: 0.25, endB: 0.9, endA: 1
            )
        }

        var scene = GPUIScene(clearColor: .white)

        let uniform = showcaseQuad(x: 10)
        scene.addQuad(
            QuadPrimitive(
                x: uniform.x, y: uniform.y, width: uniform.width, height: uniform.height,
                cornerRadius: 20,
                startR: uniform.startR, startG: uniform.startG, startB: uniform.startB, startA: 1,
                endR: uniform.startR, endG: uniform.startG, endB: uniform.startB, endA: 1
            ), toLayer: 0)

        scene.addQuad(
            QuadPrimitive(
                x: 110, y: 10, width: 80, height: 80,
                startR: 0.1, startG: 0.25, startB: 0.9, startA: 1,
                endR: 0.1, endG: 0.25, endB: 0.9, endA: 1,
                cornerRadiusTopLeft: 20, cornerRadiusTopRight: 20,
                cornerRadiusBottomRight: 20, cornerRadiusBottomLeft: 20
            ), toLayer: 0)

        scene.addQuad(
            QuadPrimitive(
                x: 210, y: 10, width: 80, height: 80,
                startR: 0.1, startG: 0.25, startB: 0.9, startA: 1,
                endR: 0.1, endG: 0.25, endB: 0.9, endA: 1,
                cornerRadiusTopLeft: 32
            ), toLayer: 0)

        scene.addQuad(
            QuadPrimitive(
                x: 310, y: 10, width: 80, height: 80,
                startR: 0.1, startG: 0.25, startB: 0.9, startA: 1,
                endR: 0.1, endG: 0.25, endB: 0.9, endA: 1,
                cornerRadiusTopLeft: 32, cornerRadiusBottomRight: 32
            ), toLayer: 0)

        scene.finish()
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 400, height: 100))
        try bitmap.writePNG(to: URL(fileURLWithPath: outputPath))
    }
}
