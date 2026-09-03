import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// The renderer-neutral contract implements multiply, screen and overlay for
/// ordinary quads on both the CPU and D3D11 paths; additive saturates their
/// premultiplied RGBA sum. Material quads, other primitive families and full View/group blend semantics
/// are separate open work. Carrier checks remain, and fixed pixel oracles plus
/// actual batch/legacy regressions replace the former blanket no-op decision.
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

    func testSeparableAndAdditiveModesHaveIndependentReferencePixels() async {
        let normal = GPUIRawSceneRasterizer.rasterize(Self.overlayScene(mode: .normal), size: Self.surface)
        let additive = GPUIRawSceneRasterizer.rasterize(Self.overlayScene(mode: .additive), size: Self.surface)
        XCTAssertNotEqual(additive.pixels, normal.pixels)
        Self.assertCenter(additive, equals: Color(red: 1, green: 0.725, blue: 1, alpha: 1))
        for (mode, expected) in Self.separableExpectedPixels {
            let rendered = GPUIRawSceneRasterizer.rasterize(Self.overlayScene(mode: mode), size: Self.surface)
            XCTAssertNotEqual(rendered.pixels, normal.pixels)
            Self.assertCenter(rendered, equals: expected)
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

    /// Every implemented separable mode must agree with the shipping batch path.
    /// The new strict WARP regressions additionally reject setup skips/fallbacks.
    func testCrossBackendAgreementForANonNormalMode() async throws {
        for (mode, expected) in Self.separableExpectedPixels {
            let scene = Self.overlayScene(mode: mode)
            let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surface)
            let gpu = try WARPBatchRenderer.render(scene, size: Self.surface)
            Self.assertCenter(cpu, equals: expected)
            let report = comparePixels(gpu, cpu, tolerance: 4)
            XCTAssertGreaterThanOrEqual(
                report.matchRatio, 0.995,
                String(
                    format: "\(mode) must render identically on both backends: %.4f within tolerance",
                    report.matchRatio))
        }
    }

    // MARK: - The frame path makes the same decision

    /// The same overlay as a `RenderFrame`, which is what the fallback
    /// presenter and `GPUISceneBridge` consume.
    private static func overlayFrame(mode: BlendMode) -> RenderFrame {
        var frame = RenderFrame(clearColor: Color(red: 0.08, green: 0.10, blue: 0.14, alpha: 1))
        frame.commands.append(
            .fillRect(
                FillRectCommand(
                    rect: Rect(x: 0, y: 0, width: 64, height: 64),
                    color: Color(red: 0.9, green: 0.2, blue: 0.4, alpha: 1))))
        frame.commands.append(
            .fillRect(
                FillRectCommand(
                    rect: Rect(x: 8, y: 8, width: 48, height: 48),
                    color: Color(red: 0.3, green: 0.7, blue: 0.9, alpha: 0.75),
                    blendMode: mode)))
        return frame
    }

    /// This is the CPU frame-to-scene bridge. Actual legacy D3D11 frame pixels
    /// are covered separately; this method must not stand in for that evidence.
    func testFrameBridgeUsesSeparableAndSaturatedAdditivePixels() async {
        let normal = GPUIRawSceneRasterizer.rasterize(Self.overlayFrame(mode: .normal), size: Self.surface)
        let additive = GPUIRawSceneRasterizer.rasterize(Self.overlayFrame(mode: .additive), size: Self.surface)
        XCTAssertNotEqual(additive.pixels, normal.pixels)
        Self.assertCenter(additive, equals: Color(red: 1, green: 0.725, blue: 1, alpha: 1))
        for (mode, expected) in Self.separableExpectedPixels {
            let rendered = GPUIRawSceneRasterizer.rasterize(Self.overlayFrame(mode: mode), size: Self.surface)
            XCTAssertNotEqual(rendered.pixels, normal.pixels)
            Self.assertCenter(rendered, equals: expected)
        }
    }

    /// And the frame path carries what the scene path carries: the bridge used
    /// to drop the mode outright, so converting a frame to a scene lost the
    /// data the reversibility argument depends on.
    func testTheModeSurvivesTheFrameToSceneBridge() async {
        let scene = GPUIScene(from: Self.overlayFrame(mode: .multiply), surfaceSize: Size(width: 64, height: 64))
        let modes = scene.layers.flatMap { $0.quads.map(\.blendMode) }
        XCTAssertTrue(
            modes.contains(Float(BlendMode.multiply.rawValue)),
            "the frame path must carry the mode exactly as the painter does")
    }

    // Opaque backdrop (.9,.2,.4), source (.3,.7,.9) at alpha .75.
    // These are fixed hand-derived values, not a call to the production helper.
    private static let separableExpectedPixels: [(BlendMode, Color)] = [
        (.multiply, Color(red: 0.4275, green: 0.155, blue: 0.37, alpha: 1)),
        (.screen, Color(red: 0.9225, green: 0.62, blue: 0.805, alpha: 1)),
        (.overlay, Color(red: 0.87, green: 0.26, blue: 0.64, alpha: 1)),
    ]

    private static func assertCenter(
        _ bitmap: BitmapSurface, equals expected: Color, file: StaticString = #filePath, line: UInt = #line
    ) {
        let offset = 32 * Int(bitmap.bytesPerRow) + 32 * 4
        XCTAssertEqual(Float(bitmap.pixels[offset + 2]) / 255, expected.red, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(Float(bitmap.pixels[offset + 1]) / 255, expected.green, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(Float(bitmap.pixels[offset]) / 255, expected.blue, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(Float(bitmap.pixels[offset + 3]) / 255, expected.alpha, accuracy: 0.01, file: file, line: line)
    }
}
