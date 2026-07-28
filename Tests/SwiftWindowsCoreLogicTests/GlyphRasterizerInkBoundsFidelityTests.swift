import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// CPU rasterizer ink-bounds fidelity at fractional display scales.
///
/// The headless comparison path (`CPUBatchRenderer` ->
/// `GPUIRawSceneRasterizer`) must rasterize exactly the glyph quads the
/// painter emitted: ink may never appear outside the quad bounds (that
/// would be a stretch), and the ink span must track the DirectWrite
/// advance span within side-bearing tolerance. This is the reference
/// half of the live-vs-headless fidelity comparison — the D3D11 half is
/// pinned at WARP level by `D3D11GlyphShaderPixelTests`.
@MainActor
final class GlyphRasterizerInkBoundsFidelityTests: XCTestCase {

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

    private struct InkBoundsSample {
        var quadMinX: Double
        var quadMaxRight: Double
        var inkMinX: Int
        var inkMaxX: Int
        var directWriteAdvanceSpan: Double
    }

    private func sample(
        text: String,
        style: PixelTextStyle,
        scale: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> InkBoundsSample? {
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

        let quads = scene.layers.flatMap(\.glyphs)
        guard !quads.isEmpty else {
            XCTFail("\(text) @\(scale)x: no native glyphs emitted", file: file, line: line)
            return nil
        }
        let quadMinX = quads.map { Double($0.screenX) }.min()!
        let quadMaxRight = quads.map { Double($0.screenX + $0.screenW) }.max()!

        let pixelWidth = Int32(((frameWidth + 40) * scale).rounded(.up))
        let pixelHeight = Int32(((frameHeight + 20) * scale).rounded(.up))
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: pixelWidth, height: pixelHeight))

        // Caption ink is white on the black clear color; treat anything
        // above the antialiasing floor as ink.
        var inkMinX = Int.max
        var inkMaxX = Int.min
        let width = Int(bitmap.width)
        let height = Int(bitmap.height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard offset + 2 < bitmap.pixels.count else { continue }
                let red = bitmap.pixels[offset + 2]
                let green = bitmap.pixels[offset + 1]
                let blue = bitmap.pixels[offset]
                if red > 24 && green > 24 && blue > 24 {
                    inkMinX = min(inkMinX, x)
                    inkMaxX = max(inkMaxX, x)
                }
            }
        }
        guard inkMinX <= inkMaxX else {
            XCTFail("\(text) @\(scale)x: CPU rasterizer produced no ink", file: file, line: line)
            return nil
        }

        let directWriteAdvanceSpan = layoutLine.glyphs.reduce(0.0) { max($0, $1.origin.x + $1.advance) } * scale
        return InkBoundsSample(
            quadMinX: quadMinX,
            quadMaxRight: quadMaxRight,
            inkMinX: inkMinX,
            inkMaxX: inkMaxX,
            directWriteAdvanceSpan: directWriteAdvanceSpan
        )
    }

    private func assertInkBounds(
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
            "\(text) weight=\(weight) size=\(size) @\(scale)x: "
            + "quads=[\(sample.quadMinX), \(sample.quadMaxRight)] ink=[\(sample.inkMinX), \(sample.inkMaxX)] "
            + "advanceSpan=\(sample.directWriteAdvanceSpan)"

        // No ink outside the emitted quads — a stretched rasterization
        // would spill past them.
        XCTAssertGreaterThanOrEqual(
            Double(sample.inkMinX), sample.quadMinX,
            "CPU ink starts left of the first glyph quad — \(details)",
            file: file, line: line)
        XCTAssertLessThanOrEqual(
            Double(sample.inkMaxX + 1), sample.quadMaxRight,
            "CPU ink extends past the last glyph quad — \(details)",
            file: file, line: line)
        // The ink must actually reach the quad bounds (no clipped or
        // shrunk rasterization): edge columns carry real antialiased ink
        // because atlas cropping keeps every nonzero coverage column.
        XCTAssertEqual(
            Double(sample.inkMinX), sample.quadMinX, accuracy: 0.51,
            "CPU ink does not reach the first quad's leading edge — \(details)",
            file: file, line: line)
        XCTAssertEqual(
            Double(sample.inkMaxX + 1), sample.quadMaxRight, accuracy: 0.51,
            "CPU ink does not reach the last quad's trailing edge — \(details)",
            file: file, line: line)
        // And the ink span tracks DirectWrite's advance span within the
        // side-bearing slack (ink is legitimately narrower than advance).
        let inkSpan = Double(sample.inkMaxX - sample.inkMinX + 1)
        XCTAssertLessThanOrEqual(
            inkSpan, sample.directWriteAdvanceSpan + 0.5 + 1e-4,
            "CPU ink wider than the DirectWrite advance span — \(details)",
            file: file, line: line)
        XCTAssertGreaterThan(
            inkSpan, sample.directWriteAdvanceSpan - 4.0,
            "CPU ink implausibly narrower than the DirectWrite advance span — \(details)",
            file: file, line: line)
    }

    func testBoldCaptionInkBoundsAcrossScales() async {
        await MainActor.run {
            for scale in [1.0, 1.25, 1.5, 2.0] {
                assertInkBounds(text: "CYCLE MODE", weight: .bold, size: 12, scale: scale)
            }
        }
    }

    func testRegularBodyInkBoundsAcrossScales() async {
        await MainActor.run {
            for scale in [1.0, 1.25, 1.5, 2.0] {
                assertInkBounds(text: "Dashboard settings", weight: .regular, size: 13, scale: scale)
            }
        }
    }
}
