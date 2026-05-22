import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Cross-DPI rendering parity. Windows hosts ship at many display scales
/// (1.0, 1.25, 1.5, 2.0, 3.0+), and SwiftUI-shape view trees must render
/// crisply at every one of them. These tests guarantee:
/// - text always reaches DirectWrite (no PixelText fallback at any DPI),
/// - primitive families fire at every scale,
/// - mid-session displayScale changes don't lose primitives or wedge
///   the renderer.
@MainActor
final class MultiDPIParityTests: XCTestCase {

    private func sampleView() -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Multi-DPI Title")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Rectangle().fill(.red).frame(width: 30, height: 24)
                    Circle().fill(.blue).frame(width: 24, height: 24)
                    Text("Inline")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
                Rectangle().fill(.white).frame(width: 80, height: 8)
                    .shadow(color: .black, radius: 3)
            }
            .padding(8)
        )
    }

    private func snapshot(displayScale: Double, size: IntSize = IntSize(width: 280, height: 160)) -> GPUIScene {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: sampleView(), size: size, displayScale: displayScale, clearColor: .black
        ).scene
    }

    func testEveryStandardDPIRendersWithNativeGlyphsAndNoPixelTextFallback() async {
        await MainActor.run {
            let scales: [Double] = [1.0, 1.25, 1.5, 2.0, 3.0]
            for scale in scales {
                let scene = snapshot(displayScale: scale)
                var nativeGlyphs = 0
                var pixelGlyphs = 0
                var quads = 0
                var shadows = 0
                for layer in scene.layers {
                    nativeGlyphs += layer.glyphs.count
                    pixelGlyphs += layer.pixelGlyphs.count
                    quads += layer.quads.count
                    shadows += layer.shadows.count
                }
                XCTAssertGreaterThan(
                    nativeGlyphs, 0,
                    "DPI \(scale): text must reach DirectWrite at every standard scale")
                XCTAssertEqual(
                    pixelGlyphs, 0,
                    "DPI \(scale): PixelText fallback must never fire at standard scales")
                XCTAssertGreaterThan(quads, 0, "DPI \(scale): quads must fire")
                XCTAssertGreaterThan(shadows, 0, "DPI \(scale): shadow must fire")
            }
        }
    }

    func testPrimitiveCountStaysConsistentAcrossDPIChanges() async {
        await MainActor.run {
            // The view tree is identical at every DPI, only the rasterized
            // pixel sizes change. So the scene-graph topology (quad count,
            // glyph count, shadow count) must be identical.
            let baseline = snapshot(displayScale: 1.0)
            let baseQuads = baseline.layers.reduce(0) { $0 + $1.quads.count }
            let baseGlyphs = baseline.layers.reduce(0) { $0 + $1.glyphs.count }
            let baseShadows = baseline.layers.reduce(0) { $0 + $1.shadows.count }
            for scale: Double in [1.25, 1.5, 2.0, 3.0] {
                let scene = snapshot(displayScale: scale)
                let q = scene.layers.reduce(0) { $0 + $1.quads.count }
                let g = scene.layers.reduce(0) { $0 + $1.glyphs.count }
                let s = scene.layers.reduce(0) { $0 + $1.shadows.count }
                XCTAssertEqual(q, baseQuads, "DPI \(scale): quad count must match 1x baseline")
                XCTAssertEqual(g, baseGlyphs, "DPI \(scale): native glyph count must match 1x baseline")
                XCTAssertEqual(s, baseShadows, "DPI \(scale): shadow count must match 1x baseline")
            }
        }
    }

    func testMidSessionDisplayScaleChangePreservesNativeGlyphPath() async {
        await MainActor.run {
            // Build a runtime once, render at 1x, then switch to 2x and
            // re-render. Both scenes must still use DirectWrite, with no
            // PixelText leak from cache reuse during the transition.
            let snap1 = WinSwiftUIRendererSnapshotter.snapshot(
                of: sampleView(),
                size: IntSize(width: 240, height: 140),
                displayScale: 1.0,
                clearColor: .black
            )
            let runtime = snap1.runtime
            runtime.displayScale = 2.0
            let scene2 = runtime.renderScene(at: 1.0)

            var nativeGlyphs1 = 0
            var pixelGlyphs1 = 0
            for layer in snap1.scene.layers {
                nativeGlyphs1 += layer.glyphs.count
                pixelGlyphs1 += layer.pixelGlyphs.count
            }
            var nativeGlyphs2 = 0
            var pixelGlyphs2 = 0
            for layer in scene2.layers {
                nativeGlyphs2 += layer.glyphs.count
                pixelGlyphs2 += layer.pixelGlyphs.count
            }
            XCTAssertGreaterThan(nativeGlyphs1, 0)
            XCTAssertGreaterThan(nativeGlyphs2, 0)
            XCTAssertEqual(pixelGlyphs1, 0)
            XCTAssertEqual(pixelGlyphs2, 0, "DPI change must not flip text into PixelText fallback")
        }
    }

    func testFractionalDPIScalesStillEmitGlyphAtlas() async {
        await MainActor.run {
            // Common Windows fractional scales 1.25 and 1.75 — historically
            // these are where snap-to-pixel rounding can drop glyphs.
            for scale: Double in [1.10, 1.25, 1.40, 1.75, 2.50] {
                let scene = snapshot(displayScale: scale)
                XCTAssertNotNil(
                    scene.glyphAtlas,
                    "Fractional DPI \(scale): a glyph atlas snapshot must be attached")
                let nativeGlyphs = scene.layers.reduce(0) { $0 + $1.glyphs.count }
                XCTAssertGreaterThan(
                    nativeGlyphs, 0,
                    "Fractional DPI \(scale): native glyphs must fire")
            }
        }
    }
}
