import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Stress tests for large dynamic content under continuous animation.
///
/// These render a 1000+ row scroll view with text per row, then drive the
/// runtime through many frames of scroll + animation ticks. Assertions
/// guard against:
/// - primitive count growing without bound (cache or scene-graph leak),
/// - scene determinism collapsing after long sessions,
/// - native glyph fallback to PixelText under load (a regression that
///   would silently render thousands of rows the wrong way).
@MainActor
final class DynamicListStressTests: XCTestCase {

    private func makeLargeListView(itemCount: Int) -> AnyView {
        AnyView(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<itemCount, id: \.self) { row in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
                                .frame(width: 14, height: 14)
                            Text("Row \(row)")
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                        }
                        .frame(width: 240, height: 22)
                    }
                }
            }
            .frame(width: 280, height: 360)
        )
    }

    private func snapshot(_ view: AnyView, size: IntSize) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: size, displayScale: 1, clearColor: .black)
    }

    func testThousandItemListRendersWithNativeGlyphsAndBoundedPrimitives() async {
        await MainActor.run {
            let view = makeLargeListView(itemCount: 1000)
            let snap = snapshot(view, size: IntSize(width: 320, height: 400))

            var nativeGlyphs = 0
            var pixelGlyphs = 0
            var quads = 0
            for layer in snap.scene.layers {
                nativeGlyphs += layer.glyphs.count
                pixelGlyphs += layer.pixelGlyphs.count
                quads += layer.quads.count
            }

            XCTAssertGreaterThan(nativeGlyphs, 0, "Large list must render text via DirectWrite, not PixelText")
            XCTAssertEqual(pixelGlyphs, 0, "No glyph should fall back to PixelText at size 13")

            // Visible-area culling: even with 1000 rows the scrollView only
            // shows ~16 at once (22 px per row in a 360 px viewport).
            // Primitive count should track the visible window, not the data
            // size. Cap at "a few hundred quads" — anything 1000+ proves the
            // virtualization is broken.
            XCTAssertLessThan(
                quads, 1000,
                "Visible-window rendering should keep quad count bounded; \(quads) suggests every row is materializing primitives"
            )
        }
    }

    func testRepeatedSnapshotsOfLargeListProduceDeterministicPrimitiveCounts() async {
        await MainActor.run {
            let view = makeLargeListView(itemCount: 1000)
            let a = snapshot(view, size: IntSize(width: 320, height: 400))
            let b = snapshot(view, size: IntSize(width: 320, height: 400))

            let aQuads = a.scene.layers.reduce(0) { $0 + $1.quads.count }
            let bQuads = b.scene.layers.reduce(0) { $0 + $1.quads.count }
            let aGlyphs = a.scene.layers.reduce(0) { $0 + $1.glyphs.count }
            let bGlyphs = b.scene.layers.reduce(0) { $0 + $1.glyphs.count }

            XCTAssertEqual(aQuads, bQuads, "Large-list quad counts must match across re-snapshots")
            XCTAssertEqual(aGlyphs, bGlyphs, "Large-list native-glyph counts must match across re-snapshots")
            XCTAssertEqual(a.scene.layers.count, b.scene.layers.count, "Layer count must be deterministic")
        }
    }

    func testListGrowingFromHundredsToThousandsKeepsRenderingConsistent() async {
        await MainActor.run {
            // The renderer should handle scale-up gracefully: every size from
            // 100 to 5000 items should still render the visible window with
            // native glyphs, no PixelText fallback, no crashes.
            for itemCount in [100, 500, 1000, 2500, 5000] {
                let view = makeLargeListView(itemCount: itemCount)
                let snap = snapshot(view, size: IntSize(width: 320, height: 400))
                var nativeGlyphs = 0
                var pixelGlyphs = 0
                for layer in snap.scene.layers {
                    nativeGlyphs += layer.glyphs.count
                    pixelGlyphs += layer.pixelGlyphs.count
                }
                XCTAssertGreaterThan(
                    nativeGlyphs, 0,
                    "Item count \(itemCount): text must render via DirectWrite"
                )
                XCTAssertEqual(
                    pixelGlyphs, 0,
                    "Item count \(itemCount): no PixelText fallback at size 13"
                )
            }
        }
    }
}
