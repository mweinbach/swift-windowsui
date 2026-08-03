import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Structural performance-budget release gates (see
/// `docs/PerformanceBudgets.md`). Every assertion here is a structural bound
/// — primitive counts, cache sizes — never wall-clock time, so the gates
/// cannot flake on a slow runner.
@MainActor
final class PerformanceBudgetGateTests: XCTestCase {

    private func snapshotScreen(
        _ screen: DemoScreen,
        size: IntSize = IntSize(width: 1280, height: 720)
    ) -> WinSwiftUIRenderSnapshot {
        let model = DemoDashboardModel()
        model.selectedScreen = screen
        return WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model),
            size: size,
            displayScale: 1
        )
    }

    private func quadCount(_ snapshot: WinSwiftUIRenderSnapshot) -> Int {
        snapshot.scene.layers.reduce(0) { $0 + $1.quads.count }
    }

    // MARK: - Demo scene primitive budgets

    func testDemoDashboardStaysWithinScenePrimitiveBudget() async {
        await MainActor.run {
            let snapshot = snapshotScreen(.dashboard)
            // Measured 2026-07: 802 primitives / 216 quads / 1 layer at
            // 1280x720. Bounds carry 2x headroom; a breach means the scene
            // graph roughly doubled, i.e. a real regression (broken culling,
            // ghost primitives), not noise.
            XCTAssertLessThan(
                snapshot.scene.primitiveCount, 1600,
                "dashboard scene primitive count must stay within budget")
            XCTAssertLessThan(
                quadCount(snapshot), 500,
                "dashboard quad count must stay within budget")
        }
    }

    func testDemoDataScreenStaysWithinScenePrimitiveBudget() async {
        await MainActor.run {
            let snapshot = snapshotScreen(.data)
            // Measured 2026-07: 582 primitives / 258 quads / 1 layer at
            // 1280x720; 2x headroom as above.
            XCTAssertLessThan(
                snapshot.scene.primitiveCount, 1200,
                "data screen scene primitive count must stay within budget")
            XCTAssertLessThan(
                quadCount(snapshot), 600,
                "data screen quad count must stay within budget")
        }
    }

    // MARK: - Work budgets (WS-20)

    // Primitive counts bound how much a scene *describes*. These bound how
    // much the engine has to *do* with it — the axis on which a 16 MB/frame
    // atlas upload, a draw-call explosion and a per-descendant blur pass are
    // all invisible. Structural counts only, no wall clock, so they cannot
    // flake on a slow runner.

    private func renderPlan(for screen: DemoScreen) throws -> D3D11BatchRenderer.RenderPlan {
        var scene = snapshotScreen(screen).scene
        scene.finish()
        // Plan against a warm renderer: the interesting number is the steady
        // state, not the first frame's binds. Every texture the scene
        // registered counts as already bound.
        let cached = D3D11BatchRenderer.CachedResources(
            hasGlyphAtlas: true,
            hasPixelGlyphAtlas: true,
            boundImageTextureIDs: Set(scene.imageResources.map(\.textureID)))
        return try D3D11BatchRenderer.makeRenderPlan(for: scene, cachedResources: cached)
    }

    /// A render step is a state change plus a draw. The step count is what
    /// batching buys, so a screen whose steps rise towards its primitive
    /// count has lost its batches — which is exactly what a blur or a
    /// texture bind per primitive does.
    func testDemoScreenRenderPlansStayWithinDrawStepBudget() async throws {
        // Measured 2026-08 at 1280x720: dashboard 100 steps / 802
        // primitives, data 84 steps / 582. Bounds carry 2x headroom, so a
        // breach means the batches themselves broke — a texture bind, a
        // blur or a clip change per primitive — not drift.
        for (screen, budget) in [(DemoScreen.dashboard, 200), (DemoScreen.data, 200)] {
            let plan = try renderPlan(for: screen)
            XCTAssertLessThan(
                plan.steps.count, budget,
                "\(screen) render plan must stay batched: \(plan.steps.count) steps")
            // And the batching must be real: several primitives per step.
            let primitives = snapshotScreen(screen).scene.primitiveCount
            XCTAssertLessThan(
                plan.steps.count * 4, primitives,
                "\(screen) must batch at least 4 primitives per draw step on average")
        }
    }

    /// The upload budget. Rendering the same content twice must upload zero
    /// atlas bytes the second time: the shared upload protocol is what makes
    /// "the atlas did not change" expressible, and a regression here is a
    /// 16 MiB memcpy on the main actor every frame that contains text.
    func testSecondIdenticalRenderUploadsNoAtlasBytes() async {
        await MainActor.run {
            let first = snapshotScreen(.dashboard)
            guard let firstAtlas = first.scene.glyphAtlas else {
                return XCTFail("the dashboard must render text, and text must carry an atlas snapshot")
            }
            let uploadedState = firstAtlas.uploadedState

            let second = snapshotScreen(.dashboard)
            guard let secondAtlas = second.scene.glyphAtlas else {
                // No snapshot at all is the strongest form of "nothing to
                // upload"; the D3D11 path reads nil as "keep your texture".
                return
            }
            XCTAssertEqual(
                secondAtlas.uploadDecision(for: uploadedState), .skip,
                "a second identical render must upload no atlas bytes")
        }
    }

    /// One `.blur()` is one pass. It used to be one backbuffer copy plus two
    /// blur passes per descendant background quad, and each of those breaks
    /// the quad batch.
    func testInheritedBlurSubtreeStaysWithinBlurPassBudget() async {
        await MainActor.run {
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: BlurBudgetProbe(rowCount: 50),
                size: IntSize(width: 320, height: 480),
                displayScale: 1)
            let blurredQuads = snapshot.scene.layers.reduce(0) {
                $0 + $1.quads.filter { $0.blurRadius > 0 }.count
            }
            XCTAssertLessThanOrEqual(
                blurredQuads, 2,
                "a blurred subtree is a bounded number of blur passes, not one per descendant; "
                    + "got \(blurredQuads) over 50 backgrounded rows")
        }
    }

    /// Layout work for a long list must scale with the viewport, not the
    /// list. `virtualizedLayoutSkipCount` is the count of row subtrees whose
    /// recursive layout the viewport made unnecessary.
    func testLazyListLayoutWorkIsProportionalToTheViewport() async {
        await MainActor.run {
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: LazyListBudgetProbe(rowCount: 500),
                size: IntSize(width: 240, height: 200),
                displayScale: 1)
            XCTAssertGreaterThan(
                snapshot.runtime.virtualizedLayoutSkipCount, 400,
                "a 500-row lazy list in a 200pt viewport must skip the recursive layout of most rows")
        }
    }

    private struct BlurBudgetProbe: View {
        let rowCount: Int
        var body: some View {
            VStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { index in
                    Text("row \(index)")
                        .frame(width: 200, height: 6)
                        .background(Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
                }
            }
            .blur(radius: 8)
        }
    }

    private struct LazyListBudgetProbe: View {
        let rowCount: Int
        var body: some View {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<rowCount, id: \.self) { index in
                        Text("row \(index)").frame(width: 220, height: 24)
                    }
                }
            }
        }
    }

    // MARK: - Text raster cache budgets

    func testTextRasterCacheEnforcesEntryCountAndMemoryBudgets() async {
        await MainActor.run {
            let cache = TextRasterCache(maxEntryCount: 4, maxMemoryBytes: 10 * 16 * 4)
            let style = PixelTextStyle(color: .white, scale: 1, alignment: .leading, weight: .regular)
            // Each surface is 4x4 BGRA = 64 bytes.
            func surface() -> BitmapSurface {
                BitmapSurface(width: 4, height: 4, bytesPerRow: 16, pixels: Data(count: 64))
            }

            // Insert 8 distinct entries: the entry-count cap (4) must bound
            // the cache even though 8 x 64 bytes fits the memory budget.
            for index in 0..<8 {
                let key = TextRasterCacheKey(
                    text: "entry \(index)", style: style, size: Size(width: 4, height: 4))
                cache.insert(surface(), for: key)
            }
            XCTAssertLessThanOrEqual(cache.count, 4, "entry-count cap must bound the cache")
            XCTAssertLessThanOrEqual(cache.currentMemoryBytes, 10 * 16 * 4)

            // The oldest entries must have been evicted (LRU).
            let oldest = TextRasterCacheKey(text: "entry 0", style: style, size: Size(width: 4, height: 4))
            let newest = TextRasterCacheKey(text: "entry 7", style: style, size: Size(width: 4, height: 4))
            XCTAssertNil(cache.get(for: oldest), "oldest entry should have been evicted")
            XCTAssertNotNil(cache.get(for: newest), "newest entry should survive")
        }
    }

    func testTextRasterCacheEnforcesMemoryBudgetBelowEntryCap() async {
        await MainActor.run {
            // Memory budget of 5 surfaces; entry cap high enough not to bind.
            let cache = TextRasterCache(maxEntryCount: 100, maxMemoryBytes: 5 * 64)
            let style = PixelTextStyle(color: .white, scale: 1, alignment: .leading, weight: .regular)
            for index in 0..<20 {
                let key = TextRasterCacheKey(
                    text: "blob \(index)", style: style, size: Size(width: 4, height: 4))
                cache.insert(
                    BitmapSurface(width: 4, height: 4, bytesPerRow: 16, pixels: Data(count: 64)),
                    for: key)
            }
            XCTAssertLessThanOrEqual(
                cache.currentMemoryBytes, 5 * 64,
                "memory budget must bound the cache below the entry cap")
            XCTAssertLessThanOrEqual(cache.count, 5)
        }
    }
}
