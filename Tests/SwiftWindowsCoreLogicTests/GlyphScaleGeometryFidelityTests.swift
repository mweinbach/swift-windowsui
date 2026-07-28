import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Emitted-glyph-geometry fidelity at fractional display scales.
///
/// Audits the real scene paint path (`ScenePainter` -> native glyph
/// emission) against the DirectWrite layout it claims to render, at
/// 1.0/1.25/1.5/2.0/2.5. The invariants pinned here are the ones the
/// glyph-quad fidelity investigation established:
///
/// 1. **No stretch**: every emitted glyph quad is exactly as wide as the
///    atlas entry its UVs select (`screenW == entryW`). A quad stretched
///    even 1px wider bleeds ink into the extra column on the GPU (pinned
///    at WARP level by `D3D11GlyphShaderPixelTests`).
/// 2. **Bounded, non-accumulating placement error**: each glyph quad
///    origin sits within 0.5px of its ideal fractional position
///    (`origin.x * scale + bearingX`). Integer snapping is deliberate
///    (crisp 1:1 texel mapping) and each glyph derives from its own
///    DirectWrite origin, so residuals never accumulate along the line.
/// 3. **Painted advance matches DirectWrite**: the advance-based span
///    reconstructed from the painted quads matches the DirectWrite
///    advance span within ~1 physical pixel at every scale.
@MainActor
final class GlyphScaleGeometryFidelityTests: XCTestCase {

    override func setUp() async throws {
        NativeGlyphAtlas.shared.resetForTesting()
    }

    private func makeStyle(weight: TextWeight, size: Double) -> PixelTextStyle {
        PixelTextStyle(
            color: .white,
            scale: 2,
            alignment: .leading,
            verticalAlignment: .top,
            letterSpacing: 1,
            lineSpacing: 2,
            insets: .zero,
            fontFamily: "Segoe UI",
            nativeFontSize: size,
            weight: weight,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )
    }

    private struct GlyphGeometrySample {
        var quadCount: Int
        var maxAbsResidual: Double
        var maxStretchError: Double
        var paintedAdvanceSpan: Double
        var directWriteAdvanceSpan: Double
        var paintedInkSpan: Double
    }

    /// Paints `text` through the real scene path and pairs each emitted
    /// glyph quad with its DirectWrite layout glyph (both are in x order;
    /// only spaces are skipped).
    private func sample(
        text: String,
        style: PixelTextStyle,
        scale: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> GlyphGeometrySample? {
        let textSystem = WindowTextSystem()
        guard
            let measured = textSystem.measure(text, style: style, maxWidth: nil, scaleFactor: scale),
            let layout = textSystem.layout(text, style: style, maxWidth: nil, scaleFactor: scale),
            let layoutLine = layout.lines.first
        else {
            XCTFail("\(text) @\(scale)x: native layout unavailable", file: file, line: line)
            return nil
        }

        let frameWidth = measured.width + 8
        let frameHeight = measured.height + 4
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: frameWidth, height: frameHeight),
            text: text,
            textStyle: style
        )
        let scene = ScenePainter.paint(
            root: node,
            clearColor: .black,
            surfaceSize: Size(width: frameWidth + 40, height: frameHeight + 20),
            displayScale: scale
        )

        let quads = scene.layers.flatMap(\.glyphs).sorted { $0.screenX < $1.screenX }
        let layoutGlyphs = layoutLine.glyphs.filter { $0.character != " " || $0.sourceIndex == nil }
        guard quads.count == layoutGlyphs.count, let lastQuad = quads.last, let lastLayout = layoutGlyphs.last
        else {
            XCTFail(
                "\(text) @\(scale)x: emitted \(quads.count) quads for \(layoutGlyphs.count) layout glyphs",
                file: file, line: line)
            return nil
        }

        var maxAbsResidual = 0.0
        var maxStretchError = 0.0
        for (quad, layoutGlyph) in zip(quads, layoutGlyphs) {
            guard let entry = NativeGlyphAtlas.shared.glyph(for: layoutGlyph, style: style, scaleFactor: scale)
            else {
                XCTFail("\(text) @\(scale)x: no atlas entry for '\(layoutGlyph.character)'", file: file, line: line)
                return nil
            }
            let uvEntryWidth = Double(quad.atlasU1 - quad.atlasU0) * 2048.0
            maxStretchError = max(
                maxStretchError,
                abs(Double(quad.screenW) - Double(entry.width)),
                abs(Double(quad.screenW) - uvEntryWidth)
            )
            let idealQuadX = layoutGlyph.origin.x * scale + Double(entry.bearingX)
            maxAbsResidual = max(maxAbsResidual, abs(Double(quad.screenX) - idealQuadX))
        }

        let directWriteAdvanceSpan = layoutGlyphs.reduce(0.0) { max($0, $1.origin.x + $1.advance) } * scale
        let firstQuad = quads[0]
        let firstLayout = layoutGlyphs[0]
        let firstEntry = NativeGlyphAtlas.shared.glyph(for: firstLayout, style: style, scaleFactor: scale)
        let lastEntry = NativeGlyphAtlas.shared.glyph(for: lastLayout, style: style, scaleFactor: scale)
        guard let firstEntry, let lastEntry else {
            XCTFail("\(text) @\(scale)x: atlas entry lookup failed", file: file, line: line)
            return nil
        }
        let paintedStart = Double(firstQuad.screenX) - Double(firstEntry.bearingX)
        let paintedEnd =
            Double(lastQuad.screenX) - Double(lastEntry.bearingX) + Double(lastLayout.advance) * scale
        let paintedAdvanceSpan = paintedEnd - paintedStart

        let minX = quads.map { Double($0.screenX) }.min() ?? 0
        let maxRight = quads.map { Double($0.screenX + $0.screenW) }.max() ?? 0

        return GlyphGeometrySample(
            quadCount: quads.count,
            maxAbsResidual: maxAbsResidual,
            maxStretchError: maxStretchError,
            paintedAdvanceSpan: paintedAdvanceSpan,
            directWriteAdvanceSpan: directWriteAdvanceSpan,
            paintedInkSpan: maxRight - minX
        )
    }

    private func assertFidelity(
        text: String,
        weight: TextWeight,
        size: Double,
        scale: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let style = makeStyle(weight: weight, size: size)
        guard let sample = sample(text: text, style: style, scale: scale, file: file, line: line) else {
            return
        }
        let details =
            "\(text) weight=\(weight) size=\(size) @\(scale)x: quads=\(sample.quadCount) "
            + "residual=\(sample.maxAbsResidual) stretch=\(sample.maxStretchError) "
            + "paintedAdvance=\(sample.paintedAdvanceSpan) directWriteAdvance=\(sample.directWriteAdvanceSpan) "
            + "inkSpan=\(sample.paintedInkSpan)"

        XCTAssertEqual(
            sample.maxStretchError, 0, accuracy: 0.01,
            "glyph quad stretched beyond its atlas entry — \(details)",
            file: file, line: line)
        XCTAssertLessThanOrEqual(
            sample.maxAbsResidual, 0.5 + 1e-4,
            "glyph placement error exceeds integer-snap bound — \(details)",
            file: file, line: line)
        XCTAssertEqual(
            sample.paintedAdvanceSpan, sample.directWriteAdvanceSpan, accuracy: 1.0,
            "painted glyph advance disagrees with DirectWrite — \(details)",
            file: file, line: line)
        // Ink may legitimately be narrower than the advance span (side
        // bearings carry no ink) but must never be wider than the snapped
        // advance span plus the snap bound.
        XCTAssertLessThanOrEqual(
            sample.paintedInkSpan, sample.directWriteAdvanceSpan + 0.5 + 1e-4,
            "painted ink overhangs the DirectWrite advance span — \(details)",
            file: file, line: line)
    }

    func testBoldCaptionGeometryAcrossScales() async {
        await MainActor.run {
            for scale in [1.0, 1.25, 1.5, 2.0, 2.5] {
                assertFidelity(text: "CYCLE MODE", weight: .bold, size: 12, scale: scale)
            }
        }
    }

    func testRegularBodyGeometryAcrossScales() async {
        await MainActor.run {
            for scale in [1.0, 1.25, 1.5, 2.0, 2.5] {
                assertFidelity(text: "Dashboard settings", weight: .regular, size: 13, scale: scale)
            }
        }
    }

    func testBoldBodyGeometryAcrossScales() async {
        await MainActor.run {
            for scale in [1.0, 1.25, 1.5, 2.0] {
                assertFidelity(text: "Dashboard settings", weight: .bold, size: 13, scale: scale)
            }
        }
    }
}
