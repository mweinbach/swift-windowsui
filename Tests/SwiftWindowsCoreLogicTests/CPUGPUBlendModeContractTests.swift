import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// The renderer-neutral contract composites source-over, and only
/// source-over.
///
/// `QuadPrimitive.blendMode` used to be honoured by exactly one of the two
/// renderers. The CPU rasterizer implemented five separable modes; the
/// HLSL declared `float blendMode;` and never read it, and the blend state
/// is a fixed `ONE / INV_SRC_ALPHA`. So `.blendMode(.multiply)` was a
/// multiply in every screenshot, gallery image and golden hash, and a
/// plain composite on the screen the user was looking at — the sharpest
/// instance of the reference renderer validating something that is not
/// shipped.
///
/// The decision this suite gates is the one WS-08 made: **the field is
/// carried, not interpreted.** The painter still lowers `.blendMode` onto
/// the primitive so the information survives for a future GPU
/// implementation (three of the five modes — multiply, screen, plusLighter
/// — are expressible as fixed-function blend states and would need batch
/// splitting; overlay is not), but no backend acts on it and the reference
/// render no longer claims otherwise.
///
/// Landing the opposite decision means implementing the modes on the GPU
/// and then deleting this suite — which is the point of having it.
@MainActor
final class CPUGPUBlendModeContractTests: XCTestCase {

    private static let surface = IntSize(width: 64, height: 64)

    /// A saturated backdrop with an overlay on top: every separable mode
    /// gives a visibly different answer here, so "identical bytes" is a
    /// real assertion rather than a degenerate one.
    private static func overlayScene(mode: BlendMode) -> GPUIScene {
        var scene = GPUIScene(clearColor: Color(red: 0.08, green: 0.10, blue: 0.14, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 64, height: 64,
                startR: 0.9, startG: 0.2, startB: 0.4, startA: 1,
                endR: 0.9, endG: 0.2, endB: 0.4, endA: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 8, y: 8, width: 48, height: 48,
                startR: 0.3, startG: 0.7, startB: 0.9, startA: 0.75,
                endR: 0.3, endG: 0.7, endB: 0.9, endA: 0.75,
                blendMode: Float(mode.rawValue)))
        scene.finish()
        return scene
    }

    func testEveryBlendModeRasterizesAsSourceOver() async {
        let reference = GPUIRawSceneRasterizer.rasterize(
            Self.overlayScene(mode: .normal), size: Self.surface)
        for mode in [BlendMode.multiply, .screen, .overlay, .additive] {
            let rendered = GPUIRawSceneRasterizer.rasterize(Self.overlayScene(mode: mode), size: Self.surface)
            XCTAssertEqual(
                rendered.pixels, reference.pixels,
                "\(mode) must composite exactly as .normal does — the shipping shader has no other option, "
                    + "so the reference renderer must not invent one")
        }
    }

    /// The other half of the contract: the mode is still *carried*, so a
    /// future GPU implementation has the data and this decision stays
    /// reversible.
    func testTheModeSurvivesOnThePrimitive() async {
        let scene = Self.overlayScene(mode: .multiply)
        let modes = scene.layers.flatMap { $0.quads.map(\.blendMode) }
        XCTAssertTrue(
            modes.contains(Float(BlendMode.multiply.rawValue)),
            "dropping the field at the contract boundary would make the decision irreversible")
    }

    /// And the shipping backend agrees, measured rather than argued: a
    /// `.multiply` overlay renders the same on WARP as on the CPU.
    func testCrossBackendAgreementForANonNormalMode() async throws {
        let scene = Self.overlayScene(mode: .multiply)
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surface)
        let gpu = try WARPBatchRenderer.render(scene, size: Self.surface)
        let report = comparePixels(gpu, cpu, tolerance: 4)
        XCTAssertGreaterThanOrEqual(
            report.matchRatio, 0.995,
            String(
                format: "a .multiply overlay must render identically on both backends: %.4f within tolerance",
                report.matchRatio))
    }
}
