import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
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
