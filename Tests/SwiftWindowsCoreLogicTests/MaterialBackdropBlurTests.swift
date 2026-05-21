import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// End-to-end tests for backdrop-blurred `Material` backgrounds.
///
/// SwiftUI's `.regularMaterial`/`.thinMaterial`/etc. apply a tinted
/// backdrop blur. WinSwiftUI rendered them as flat translucent quads
/// until now; this suite proves each kind emits a blurred fill quad
/// through the existing `QuadPrimitive.blurRadius` path, with the
/// expected radius per material.
@MainActor
final class MaterialBackdropBlurTests: XCTestCase {

    private func sceneFor(material: Material) -> GPUIScene {
        let view = Text("Hello")
            .foregroundColor(.white)
            .padding(20)
            .background(material)
            .frame(width: 200, height: 80)
        return WinSwiftUIRendererSnapshotter.snapshot(
            of: view,
            size: IntSize(width: 240, height: 120),
            displayScale: 1,
            clearColor: .black
        ).scene
    }

    private func maxQuadBlurRadius(in scene: GPUIScene) -> Float {
        var maxBlur: Float = 0
        for layer in scene.layers {
            for quad in layer.quads where quad.blurRadius > maxBlur {
                maxBlur = quad.blurRadius
            }
        }
        return maxBlur
    }

    func testRegularMaterialEmitsBlurredBackgroundQuad() async {
        await MainActor.run {
            let scene = sceneFor(material: .regular)
            let blur = maxQuadBlurRadius(in: scene)
            XCTAssertGreaterThan(
                blur, 0,
                "`.background(.regularMaterial)` must emit a quad with non-zero blurRadius — otherwise material is just a flat translucent panel"
            )
        }
    }

    func testEachMaterialKindUsesItsDocumentedBlurRadius() async {
        await MainActor.run {
            // Pulled from Material.retainedBlurRadius. If this mapping
            // changes the test forces an update so the doc and the test
            // stay aligned.
            let expected: [(Material, Double)] = [
                (.ultraThin, 8),
                (.thin, 14),
                (.regular, 22),
                (.thick, 30),
                (.ultraThick, 40),
                (.bar, 18),
            ]
            for (material, expectedBlur) in expected {
                let scene = sceneFor(material: material)
                let actual = Double(maxQuadBlurRadius(in: scene))
                XCTAssertEqual(
                    actual, expectedBlur, accuracy: 0.001,
                    "Material kind blur radius mismatch — expected \(expectedBlur)px for kind"
                )
            }
        }
    }

    func testNonMaterialShapeStyleStillProducesUnblurredBackground() async {
        await MainActor.run {
            // Sanity: existing solid-color backgrounds must continue to
            // produce zero-blur quads. The materialFill path mustn't
            // accidentally affect the standard color path.
            let view = Text("Hello")
                .foregroundColor(.white)
                .padding(20)
                .background(Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
                .frame(width: 200, height: 80)
            let scene = WinSwiftUIRendererSnapshotter.snapshot(
                of: view, size: IntSize(width: 240, height: 120), displayScale: 1, clearColor: .black
            ).scene
            let blur = maxQuadBlurRadius(in: scene)
            XCTAssertEqual(
                blur, 0,
                "Solid-color backgrounds must not produce a blurred quad — only Material does"
            )
        }
    }
}
