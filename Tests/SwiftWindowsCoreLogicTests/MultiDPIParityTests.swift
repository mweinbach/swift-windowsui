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

    /// Dragging a window between a 100% monitor and a 150% one must leave it
    /// crisp on both. The glyph cache key is the device pixel size, so the
    /// second scale is a cache *miss* by construction and the run
    /// re-rasterizes rather than reusing cells sized for the old monitor —
    /// this pins that, because the failure is invisible in a primitive count
    /// and shows up only as blurred text on the monitor you moved to.
    func testDisplayScaleChangeReRasterizesGlyphsAtTheNewDeviceSize() async {
        await MainActor.run {
            NativeGlyphAtlas.shared.resetForTesting()
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: sampleView(),
                size: IntSize(width: 280, height: 160),
                displayScale: 1.0,
                clearColor: .black
            )
            let runtime = snapshot.runtime
            let cellsAtOneX = snapshot.scene.layers.flatMap { $0.glyphs.map(\.screenH) }.sorted()
            XCTAssertFalse(cellsAtOneX.isEmpty)
            let rastersAtOneX = NativeGlyphAtlas.shared.cachedGlyphCount
            XCTAssertGreaterThan(rastersAtOneX, 0)

            for scale: Double in [1.25, 1.5, 2.0] {
                runtime.displayScale = scale
                let scene = runtime.renderScene(at: 1.0)
                let cells = scene.layers.flatMap { $0.glyphs.map(\.screenH) }.sorted()
                XCTAssertEqual(
                    cells.count, cellsAtOneX.count, "@\(scale)x: the same run must emit the same glyph count")

                // The cells grew with the scale — the run is drawing from
                // rasters made for this monitor, not from the 1x ones.
                // Compared in aggregate rather than glyph by glyph: an ink
                // box is quantized to whole pixels, so an individual cell can
                // round either way, but the whole run cannot.
                let inkAtScale = cells.reduce(0) { $0 + Double($1) }
                let inkAtOneX = cellsAtOneX.reduce(0) { $0 + Double($1) }
                XCTAssertEqual(
                    inkAtScale / inkAtOneX, scale, accuracy: 0.08,
                    "@\(scale)x: total glyph cell height grew by \(inkAtScale / inkAtOneX)x, not \(scale)x — "
                        + "the run is not being rasterized for this display scale")
                XCTAssertGreaterThan(
                    NativeGlyphAtlas.shared.cachedGlyphCount, rastersAtOneX,
                    "@\(scale)x: the atlas must hold new rasters for the new device size, not reuse the 1x ones")
            }
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

    // MARK: - Ink sharpness at fractional scale

    /// Mean 10–90% coverage ramp, in device pixels, over every horizontal ink
    /// edge of a rasterized run.
    ///
    /// This is the measurable form of "crisp". A glyph rasterized at its
    /// effective device size has edges one antialiasing step wide *however
    /// many* device pixels it spans, so the ramp is flat in scale. A glyph
    /// rasterized once at 1x and then stretched has edges the stretch widened,
    /// so its ramp grows with the scale factor. The two are far enough apart
    /// that no tolerance argument is needed — see the control below.
    private func meanEdgeRamp(_ rows: [[Double]]) -> Double {
        var widths: [Double] = []
        for row in rows {
            var index = 0
            while index < row.count - 1 {
                guard row[index] <= 0.1, row[index + 1] > 0.1 else {
                    index += 1
                    continue
                }
                var end = index + 1
                while end < row.count, row[end] < 0.9 { end += 1 }
                if end < row.count { widths.append(Double(end - index)) }
                index = max(end, index + 1)
            }
        }
        guard !widths.isEmpty else { return 0 }
        return widths.reduce(0, +) / Double(widths.count)
    }

    private func coverageRows(_ text: String, size: Double, scaleFactor: Double) -> [[Double]] {
        let style = PixelTextStyle(
            color: .white,
            scale: 2,
            alignment: .leading,
            verticalAlignment: .top,
            letterSpacing: 1,
            lineSpacing: 0,
            insets: .zero,
            fontFamily: SystemUIFontFace.family(forPointSize: size),
            nativeFontSize: size,
            weight: .regular,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )
        guard let bitmap = DirectWriteTextRenderer.rasterize(text, style: style, scaleFactor: scaleFactor) else {
            return []
        }
        let width = Int(bitmap.width)
        let height = Int(bitmap.height)
        let stride = Int(bitmap.bytesPerRow)
        let bytes = [UInt8](bitmap.pixels)
        var rows: [[Double]] = []
        rows.reserveCapacity(height)
        for y in 0..<height {
            var row = [Double](repeating: 0, count: width)
            for x in 0..<width {
                let offset = y * stride + x * 4
                guard offset + 3 < bytes.count else { continue }
                row[x] = Double(max(bytes[offset], max(bytes[offset + 1], bytes[offset + 2]))) / 255.0
            }
            rows.append(row)
        }
        return rows
    }

    /// Bilinear magnification of a coverage field: the failure mode this test
    /// exists to exclude, produced deliberately so the metric is shown to be
    /// able to see it.
    private func bilinearlyUpscaled(_ rows: [[Double]], by factor: Double) -> [[Double]] {
        guard let first = rows.first, !first.isEmpty else { return rows }
        let sourceHeight = rows.count
        let sourceWidth = first.count
        let height = Int((Double(sourceHeight) * factor).rounded())
        let width = Int((Double(sourceWidth) * factor).rounded())
        var out: [[Double]] = []
        out.reserveCapacity(height)
        for y in 0..<height {
            let sourceY = min(Double(sourceHeight - 1), max(0, (Double(y) + 0.5) / factor - 0.5))
            let y0 = Int(sourceY.rounded(.down))
            let y1 = min(sourceHeight - 1, y0 + 1)
            let fy = sourceY - Double(y0)
            var row = [Double](repeating: 0, count: width)
            for x in 0..<width {
                let sourceX = min(Double(sourceWidth - 1), max(0, (Double(x) + 0.5) / factor - 0.5))
                let x0 = Int(sourceX.rounded(.down))
                let x1 = min(sourceWidth - 1, x0 + 1)
                let fx = sourceX - Double(x0)
                let top = rows[y0][x0] * (1 - fx) + rows[y0][x1] * fx
                let bottom = rows[y1][x0] * (1 - fx) + rows[y1][x1] * fx
                row[x] = top * (1 - fy) + bottom * fy
            }
            out.append(row)
        }
        return out
    }

    /// 1.25 and 1.5 are the two scales Windows users actually run at, and the
    /// two this stack could never check by eye. A glyph at either must be a
    /// fresh raster at the device size, not a magnified 1x one.
    func testFractionalScaleGlyphsAreRasterizedAtDeviceSizeNotMagnified() async {
        await MainActor.run {
            let sample = "Handgloves 0123"
            for size: Double in [13, 26] {
                let baseRows = coverageRows(sample, size: size, scaleFactor: 1.0)
                XCTAssertFalse(baseRows.isEmpty, "\(size)pt: DirectWrite must produce a 1x raster")
                let baseRamp = meanEdgeRamp(baseRows)
                XCTAssertGreaterThan(baseRamp, 0, "\(size)pt: the 1x raster must have measurable ink edges")

                for scale: Double in [1.25, 1.5, 1.75, 2.0] {
                    let rows = coverageRows(sample, size: size, scaleFactor: scale)
                    XCTAssertFalse(rows.isEmpty, "\(size)pt @\(scale)x: DirectWrite must produce a raster")

                    // The raster is genuinely device-sized, not the 1x one.
                    XCTAssertEqual(
                        rows.count, Int((Double(baseRows.count) * scale).rounded()), accuracy: 1,
                        "\(size)pt @\(scale)x: the raster must be \(scale)x as tall as the 1x raster")

                    let fresh = meanEdgeRamp(rows)
                    let magnified = meanEdgeRamp(bilinearlyUpscaled(baseRows, by: scale))

                    // The metric can see the failure it is guarding against.
                    XCTAssertGreaterThan(
                        magnified, fresh * 1.5,
                        "\(size)pt @\(scale)x: control — a magnified 1x raster must measure visibly softer, "
                            + "otherwise this test proves nothing")
                    // And the real raster is on the crisp side of it.
                    XCTAssertLessThan(
                        fresh, magnified * 0.75,
                        "\(size)pt @\(scale)x: text is being magnified from a 1x raster instead of rasterized "
                            + "at the device size")
                    // Crispness does not decay with scale: the ramp is a
                    // property of the antialiaser, not of the scale factor.
                    XCTAssertLessThan(
                        fresh, baseRamp * 1.3,
                        "\(size)pt @\(scale)x: edge ramp grew with display scale (\(fresh) vs \(baseRamp) at 1x)")
                }
            }
        }
    }

    /// The atlas quantizes *content* scale to rungs of `2^(1/8)`, which would
    /// resample 1.25 by 3.7% and 1.5 by 2.8% — at exactly the two DPI settings
    /// that matter — if display scale ever went through it. It must not: the
    /// painter multiplies display scale in un-quantized, and the only way to
    /// keep that true is to pin the glyph cells it emits.
    func testDisplayScaleReachesTheRasterizerUnquantized() async {
        await MainActor.run {
            // The quantizer is real; this test is not vacuous.
            XCTAssertNotEqual(
                NativeGlyphAtlas.glyphRasterScale(for: 1.25), 1.25, accuracy: 0.001,
                "the rung quantizer must actually distort 1.25, or this test guards nothing")
            XCTAssertNotEqual(
                NativeGlyphAtlas.glyphRasterScale(for: 1.5), 1.5, accuracy: 0.001,
                "the rung quantizer must actually distort 1.5, or this test guards nothing")

            let style = PixelTextStyle(
                color: .white,
                scale: 2,
                alignment: .leading,
                verticalAlignment: .top,
                letterSpacing: 1,
                lineSpacing: 0,
                insets: .zero,
                fontFamily: SystemUIFontFace.family(forPointSize: 26),
                nativeFontSize: 26,
                weight: .bold,
                lineBreakMode: .truncateTail,
                maximumNumberOfLines: 1
            )

            for scale: Double in [1.25, 1.5, 1.75] {
                NativeGlyphAtlas.shared.resetForTesting()
                let scene = WinSwiftUIRendererSnapshotter.snapshot(
                    of: AnyView(
                        Text("Handgloves")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)),
                    size: IntSize(width: Int32(320 * scale), height: Int32(80 * scale)),
                    displayScale: scale,
                    clearColor: .black
                ).scene
                let cellHeights = Set(scene.layers.flatMap { $0.glyphs.map { $0.screenH } })
                XCTAssertFalse(cellHeights.isEmpty, "@\(scale)x: the run must emit glyph cells")

                // What the cells would be if display scale were fed through
                // the rung quantizer, versus fed in directly.
                let quantized = NativeGlyphAtlas.glyphRasterScale(for: scale) * scale
                guard
                    let direct = NativeGlyphAtlas.shared.prepareGlyph(
                        for: Character("H"), style: style, scaleFactor: scale)?.previewEntry,
                    let viaRung = NativeGlyphAtlas.shared.prepareGlyph(
                        for: Character("H"), style: style, scaleFactor: quantized)?.previewEntry
                else {
                    XCTFail("@\(scale)x: the atlas must rasterize a reference glyph")
                    return
                }
                XCTAssertNotEqual(
                    direct.height, viaRung.height,
                    "@\(scale)x: the two candidate rasters must differ, or this test cannot tell them apart")
                XCTAssertTrue(
                    cellHeights.contains(Float(direct.height)),
                    "@\(scale)x: no emitted glyph cell matches the un-quantized device raster "
                        + "(\(direct.height)px); cells were \(cellHeights.sorted())")
                XCTAssertFalse(
                    cellHeights.contains(Float(viaRung.height)),
                    "@\(scale)x: a glyph cell matches the rung-quantized raster (\(viaRung.height)px) — "
                        + "display scale is being quantized before it reaches DirectWrite")
            }
        }
    }
}
