import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Verifies that the `QuadPrimitive.blurRadius` field — used by Material
/// backgrounds for backdrop blur — flows all the way through to the
/// D3D11 pixel shader, not just the CPU rasterizer.
///
/// Without GPU access we cannot exercise the shader at runtime, so this
/// suite validates the static contract: the QuadInstance HLSL struct
/// declares the field, the vertex shader passes it through to the pixel
/// shader stage, and the pixel shader actually consumes it (`input.blurRadius`).
/// Together with `MaterialBackdropBlurTests` (which proves the scene
/// emits a quad with non-zero blurRadius) this closes the loop:
/// scene → primitive → GPU instance → shader output.
final class D3D11QuadBlurVerificationTests: XCTestCase {

    func testQuadShaderSourceDeclaresBlurRadiusInInstanceBuffer() {
        // The QuadInstance HLSL struct must have `blurRadius` at the
        // same logical slot as the Swift `QuadPrimitive.blurRadius` so
        // the per-frame structured buffer copies through correctly.
        XCTAssertTrue(
            batchQuadShaderSource.contains("float blurRadius;"),
            "D3D11 QuadInstance HLSL must declare a blurRadius float")
    }

    func testQuadVertexShaderForwardsBlurRadiusToPixelStage() {
        // The vertex shader must pipe `inst.blurRadius` into the
        // VS->PS interpolator, otherwise the pixel shader can't read
        // it.
        XCTAssertTrue(
            batchQuadShaderSource.contains("output.blurRadius = inst.blurRadius;"),
            "Vertex shader must forward inst.blurRadius to the pixel stage")
        XCTAssertTrue(
            batchQuadShaderSource.contains("float blurRadius : TEXCOORD"),
            "VS->PS struct must include the blurRadius interpolator")
    }

    func testQuadPixelShaderConsumesBlurRadius() {
        // The pixel shader must actually use `input.blurRadius` to
        // affect the rendered pixel — otherwise the field is dead.
        XCTAssertTrue(
            batchQuadShaderSource.contains("input.blurRadius"),
            "Pixel shader must consume input.blurRadius (otherwise the field is dead and Material backgrounds wouldn't blur on the GPU path)"
        )
    }

    func testQuadPrimitiveCarriesBlurRadiusField() {
        // Sanity: the Swift-side QuadPrimitive struct exposes
        // blurRadius (this is the field the painter sets from
        // Material's retainedBlurRadius). Reading a default-constructed
        // primitive must succeed.
        let primitive = QuadPrimitive(blurRadius: 22)
        XCTAssertEqual(primitive.blurRadius, 22, accuracy: 0.001)
    }

    @MainActor
    func testMaterialSceneProducesQuadConsumedByD3D11Shader() async {
        await MainActor.run {
            // Build a scene with a regular-material background. The
            // resulting scene must have a quad whose blurRadius is the
            // material's documented radius — that's the same field the
            // D3D11 shader reads. End-to-end verification: WinSwiftUI
            // → ScenePainter → QuadPrimitive → D3D11 instance buffer.
            let view = Text("Material")
                .foregroundColor(.white)
                .padding(20)
                .background(.regularMaterial)
                .frame(width: 200, height: 80)
            let scene = WinSwiftUIRendererSnapshotter.snapshot(
                of: view, size: IntSize(width: 240, height: 120), displayScale: 1, clearColor: .black
            ).scene

            var maxBlur: Float = 0
            for layer in scene.layers {
                for quad in layer.quads where quad.blurRadius > maxBlur {
                    maxBlur = quad.blurRadius
                }
            }
            XCTAssertEqual(
                Double(maxBlur), Material.regular.retainedBlurRadius, accuracy: 0.001,
                "Material's backdrop quad must carry the kind-specific blur radius that the D3D11 shader will read"
            )
        }
    }
}
