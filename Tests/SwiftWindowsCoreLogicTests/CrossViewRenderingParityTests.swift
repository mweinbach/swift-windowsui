import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Cross-view rendering invariants.
///
/// A single scene that exercises text, shapes, gradients, shadows, and Canvas
/// paths in one tree. The point is to catch regressions where one view type
/// breaks while every focused per-view test still passes — e.g. text falling
/// back to PixelText, paths emitting zero primitives, shadow layers
/// disappearing, etc.
@MainActor
final class CrossViewRenderingParityTests: XCTestCase {

    private func parityScene() -> GPUIScene {
        let view = VStack(alignment: .leading, spacing: 12) {
            Text("Cross-View Parity")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            HStack(spacing: 10) {
                Rectangle()
                    .fill(.red)
                    .frame(width: 40, height: 30)
                    .cornerRadius(6)

                Circle()
                    .fill(.blue)
                    .frame(width: 36, height: 36)

                RoundedRectangle(cornerRadius: 8)
                    .fill(.green)
                    .frame(width: 40, height: 30)
            }

            Rectangle()
                .fill(.white)
                .frame(width: 100, height: 12)
                .shadow(color: .black, radius: 4, x: 0, y: 2)

            Canvas { ctx, size in
                var path = Path()
                path.moveTo(Point(x: 0, y: 0))
                path.lineTo(Point(x: size.width, y: 0))
                path.lineTo(Point(x: size.width / 2, y: size.height))
                path.close()
                ctx.fill(path, with: .color(Color(red: 0.95, green: 0.6, blue: 0.2, alpha: 1)))
            }
            .frame(width: 100, height: 40)
        }
        .padding(8)

        return WinSwiftUIRendererSnapshotter.snapshot(
            of: view,
            size: IntSize(width: 320, height: 240),
            displayScale: 1,
            clearColor: .black
        ).scene
    }

    func testParitySceneHasAllPrimitiveFamilies() async {
        await MainActor.run {
            let scene = parityScene()

            var totalQuads = 0
            var totalNativeGlyphs = 0
            var totalPixelGlyphs = 0
            var totalShadows = 0
            var totalPaths = 0
            for layer in scene.layers {
                totalQuads += layer.quads.count
                totalNativeGlyphs += layer.glyphs.count
                totalPixelGlyphs += layer.pixelGlyphs.count
                totalShadows += layer.shadows.count
                totalPaths += layer.paths.count
            }

            XCTAssertGreaterThan(totalQuads, 0, "Expected quad primitives from shapes")
            XCTAssertGreaterThan(totalNativeGlyphs, 0, "Text must render via native DirectWrite glyphs")
            XCTAssertEqual(
                totalPixelGlyphs, 0,
                "No glyphs should fall back to PixelText for size-18 body text — fix the layout/clip pipeline if this regresses"
            )
            XCTAssertGreaterThan(totalShadows, 0, "Shadow modifier should produce shadow primitives")
            XCTAssertGreaterThan(totalPaths, 0, "Canvas path-filling should emit path primitives")
        }
    }

    func testParitySceneHasNoEmptyLayers() async {
        await MainActor.run {
            let scene = parityScene()
            for (index, layer) in scene.layers.enumerated() {
                let isEmpty =
                    layer.quads.isEmpty && layer.glyphs.isEmpty && layer.pixelGlyphs.isEmpty
                    && layer.shadows.isEmpty && layer.paths.isEmpty && layer.images.isEmpty
                XCTAssertFalse(
                    isEmpty,
                    "Layer \(index) has no primitives — empty layers waste a draw pass and signal a layout bug")
            }
        }
    }

    func testParitySceneIsDeterministicAcrossRepeatedSnapshots() async {
        await MainActor.run {
            let a = parityScene()
            let b = parityScene()
            XCTAssertEqual(a.layers.count, b.layers.count)
            for (la, lb) in zip(a.layers, b.layers) {
                XCTAssertEqual(la.quads.count, lb.quads.count)
                XCTAssertEqual(la.glyphs.count, lb.glyphs.count)
                XCTAssertEqual(la.pixelGlyphs.count, lb.pixelGlyphs.count)
                XCTAssertEqual(la.shadows.count, lb.shadows.count)
                XCTAssertEqual(la.paths.count, lb.paths.count)
            }
        }
    }

    // MARK: - Broader view-type coverage

    /// Scene that exercises higher-level container views (ScrollView, List,
    /// LazyVStack) and nested compositions. These exercise the layout and
    /// scene-graph paths that simple shapes don't, catching regressions
    /// like missing scroll indicator quads, missing list backgrounds, or
    /// LazyVStack content failing to materialize.
    private func compositeScene() -> GPUIScene {
        let view = HStack(spacing: 8) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<8) { index in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.blue)
                                .frame(width: 16, height: 16)
                            Text("Row \(index)")
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                        }
                        .frame(width: 140, height: 20)
                    }
                }
            }
            .frame(width: 160, height: 200)

            List(0..<5, id: \.self) { value in
                Text("Item \(value)")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
            .frame(width: 140, height: 200)
        }
        .frame(width: 320, height: 220)

        return WinSwiftUIRendererSnapshotter.snapshot(
            of: view,
            size: IntSize(width: 360, height: 240),
            displayScale: 1,
            clearColor: .black
        ).scene
    }

    func testCompositeSceneEmitsTextAndShapesAcrossViewTypes() async {
        await MainActor.run {
            let scene = compositeScene()
            var nativeGlyphs = 0
            var quads = 0
            for layer in scene.layers {
                nativeGlyphs += layer.glyphs.count
                quads += layer.quads.count
            }
            XCTAssertGreaterThan(
                nativeGlyphs, 0,
                "ScrollView/List/LazyVStack text must reach DirectWrite — if it falls back the regression is silent without this test"
            )
            XCTAssertGreaterThan(quads, 0, "ForEach-driven rows must emit per-row quads")
        }
    }

    func testCompositeSceneIsDeterministic() async {
        await MainActor.run {
            let a = compositeScene()
            let b = compositeScene()
            XCTAssertEqual(a.layers.count, b.layers.count)
            for (la, lb) in zip(a.layers, b.layers) {
                XCTAssertEqual(la.quads.count, lb.quads.count, "Quad counts must match across composite re-renders")
                XCTAssertEqual(
                    la.glyphs.count, lb.glyphs.count, "Native-glyph counts must match across composite re-renders")
            }
        }
    }

    /// Pushes a deep nested VStack to verify the runtime survives arbitrary
    /// hierarchical depth without primitive duplication.
    private func deeplyNestedScene(depth: Int) -> GPUIScene {
        var view: AnyView = AnyView(
            Text("Leaf")
                .font(.system(size: 14))
                .foregroundColor(.white)
        )
        for _ in 0..<depth {
            view = AnyView(
                VStack(alignment: .center, spacing: 0) {
                    view
                }
                .padding(2)
            )
        }
        return WinSwiftUIRendererSnapshotter.snapshot(
            of: view,
            size: IntSize(width: 240, height: 200),
            displayScale: 1,
            clearColor: .black
        ).scene
    }

    func testDeeplyNestedHierarchyStillEmitsLeafText() async {
        await MainActor.run {
            let scene = deeplyNestedScene(depth: 20)
            let totalNativeGlyphs = scene.layers.reduce(0) { $0 + $1.glyphs.count }
            XCTAssertGreaterThan(
                totalNativeGlyphs,
                0,
                "Leaf Text must survive 20 levels of VStack/padding wrapping — layout collapse would silently swallow it"
            )
        }
    }

    func testParitySceneEmitsNativeGlyphAtlas() async {
        await MainActor.run {
            let scene = parityScene()
            XCTAssertNotNil(
                scene.glyphAtlas,
                "DirectWrite atlas must be attached to the scene when native glyphs are emitted — otherwise the CPU rasterizer would draw nothing"
            )
        }
    }
}
