import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class NativeTextConversionSafetyTests: XCTestCase {
    private var coveragePixels: [UInt8] {
        (0...255).flatMap { intensity in
            [UInt8(intensity), UInt8(intensity / 2), 0, 255]
        }
    }

    /// The previous arithmetic, used only with finite channels in 0...1.
    /// This catches changes from Float to Double multiplication or from
    /// truncation to nearest rounding even when the output looks similar.
    private func legacyTint(_ pixels: [UInt8], color: Color) -> [UInt8] {
        let red = Int(color.red * 255)
        let green = Int(color.green * 255)
        let blue = Int(color.blue * 255)
        var output = pixels
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let coverage = max(pixels[index], pixels[index + 1], pixels[index + 2])
            let alpha = Int(Double(coverage) * Double(color.alpha))
            output[index] = UInt8(blue * alpha / 255)
            output[index + 1] = UInt8(green * alpha / 255)
            output[index + 2] = UInt8(red * alpha / 255)
            output[index + 3] = UInt8(alpha)
        }
        return output
    }

    func testOrdinaryColorsPreserveEveryCoverageAndTruncationStep() async {
        let source = coveragePixels
        for component in 0...255 {
            let color = Color(
                red: Float(component) / 255,
                green: Float(255 - component) / 255,
                blue: 0.500_000_06,
                alpha: Float((component * 37) % 256) / 255)
            var pixels = source
            GDIRasterTextRenderer.tint(pixelBytes: &pixels, style: PixelTextStyle(color: color))
            XCTAssertEqual(pixels, legacyTint(source, color: color), "channel sample \(component)")
        }

        var pixels: [UInt8] = [255, 255, 255, 0, 128, 128, 128, 0]
        GDIRasterTextRenderer.tint(
            pixelBytes: &pixels, style: PixelTextStyle(color: Color(red: 0.5, green: 0.25, blue: 0.75, alpha: 0.5)))
        XCTAssertEqual(pixels, [95, 31, 63, 127, 47, 15, 31, 64])
    }

    func testMalformedAndExtendedRGBChannelsSaturateBeforeConversion() async {
        let cases: [(Float, UInt8)] = [
            (.nan, 0), (.infinity, 255), (-.infinity, 0),
            (.greatestFiniteMagnitude, 255), (-.greatestFiniteMagnitude, 0),
            (16, 255), (-16, 0), (.leastNonzeroMagnitude, 0), (0.5, 127),
        ]
        for (value, expected) in cases {
            for channel in 0..<3 {
                var color = Color(red: 0.25, green: 0.25, blue: 0.25)
                switch channel {
                case 0: color.blue = value
                case 1: color.green = value
                default: color.red = value
                }
                var pixels: [UInt8] = [255, 255, 255, 0]
                GDIRasterTextRenderer.tint(pixelBytes: &pixels, style: PixelTextStyle(color: color))
                var expectedPixel: [UInt8] = [63, 63, 63, 255]
                expectedPixel[channel] = expected
                XCTAssertEqual(pixels, expectedPixel, "channel \(channel), value \(value)")
            }
        }
    }

    func testMalformedAlphaIsBoundedAndNaNBecomesTransparent() async {
        let cases: [(Float, UInt8)] = [
            (.nan, 0), (.infinity, 255), (-.infinity, 0),
            (.greatestFiniteMagnitude, 255), (-.greatestFiniteMagnitude, 0),
            (2, 255), (-1, 0), (.leastNonzeroMagnitude, 0), (0.5, 127),
        ]
        for (alpha, expected) in cases {
            var pixels: [UInt8] = [255, 255, 255, 0]
            GDIRasterTextRenderer.tint(
                pixelBytes: &pixels, style: PixelTextStyle(color: Color(red: 1, green: 1, blue: 1, alpha: alpha)))
            XCTAssertEqual(pixels, [expected, expected, expected, expected], "alpha \(alpha)")
        }
    }

    func testSanitizedColorsRemainPremultipliedForPartialCoverage() async {
        let alphas: [Float] = [.nan, -.infinity, .infinity, -10, 0, 0.3, 1, 10]
        for alpha in alphas {
            var pixels = coveragePixels
            GDIRasterTextRenderer.tint(
                pixelBytes: &pixels,
                style: PixelTextStyle(
                    color: Color(red: .infinity, green: .nan, blue: .greatestFiniteMagnitude, alpha: alpha)))
            for index in stride(from: 0, to: pixels.count, by: 4) {
                XCTAssertLessThanOrEqual(pixels[index], pixels[index + 3])
                XCTAssertLessThanOrEqual(pixels[index + 1], pixels[index + 3])
                XCTAssertLessThanOrEqual(pixels[index + 2], pixels[index + 3])
                XCTAssertEqual(pixels[index + 1], 0)
            }
            XCTAssertEqual(Array(pixels.prefix(4)), [0, 0, 0, 0])
        }
    }

    func testEmptyAndIncompletePixelBuffersRemainSafe() async {
        let style = PixelTextStyle(color: Color(red: .nan, green: .infinity, blue: -.infinity, alpha: .nan))
        var empty: [UInt8] = []
        GDIRasterTextRenderer.tint(pixelBytes: &empty, style: style)
        XCTAssertTrue(empty.isEmpty)
        var pixels: [UInt8] = [255, 255, 255, 255, 7, 8, 9]
        GDIRasterTextRenderer.tint(pixelBytes: &pixels, style: style)
        XCTAssertEqual(pixels, [0, 0, 0, 0, 7, 8, 9])
    }

    func testRealGDIRasterMatchesExplicitlyClampedColor() async throws {
        let saturated = try XCTUnwrap(
            GDIRasterTextRenderer.rasterize(
                "Tint", in: Size(width: 64, height: 32),
                style: PixelTextStyle(color: Color(red: 1, green: 0, blue: 0, alpha: 1), nativeFontSize: 16),
                scaleFactor: 1))
        let malformed = try XCTUnwrap(
            GDIRasterTextRenderer.rasterize(
                "Tint", in: Size(width: 64, height: 32),
                style: PixelTextStyle(
                    color: Color(red: .greatestFiniteMagnitude, green: .nan, blue: -.infinity, alpha: .infinity),
                    nativeFontSize: 16),
                scaleFactor: 1))

        XCTAssertEqual(malformed.pixels, saturated.pixels)
        XCTAssertEqual(malformed.format.alphaMode, .premultiplied)
        let bytes = [UInt8](malformed.pixels)
        XCTAssertTrue(stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 })
    }

    func testRealGDIRasterWithNaNOpacityProducesTransparentPixels() async throws {
        let bitmap = try XCTUnwrap(
            GDIRasterTextRenderer.rasterize(
                "Tint", in: Size(width: 64, height: 32),
                style: PixelTextStyle(color: Color(red: 1, green: 1, blue: 1, alpha: .nan), nativeFontSize: 16),
                scaleFactor: 1))
        XCTAssertTrue(bitmap.pixels.allSatisfy { $0 == 0 })
    }

    func testGDIFontDimensionsKeepOrdinaryRoundingAndRejectInvalidInput() async {
        let widths: [(TextFontWidth, Int32)] = [(.standard, 0), (.compressed, 6), (.condensed, 7), (.expanded, 11)]
        for (width, expected) in widths {
            let style = PixelTextStyle(color: .white, nativeFontSize: 13.5, fontWidth: width)
            let dimensions = GDIRasterTextRenderer.fontDimensions(for: style, scaleFactor: 1.25)
            XCTAssertEqual(dimensions?.height, 17)
            XCTAssertEqual(dimensions?.width, expected)
        }

        let invalidValues: [Double] = [
            .nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -1, 0,
        ]
        for invalid in invalidValues {
            let invalidFont = PixelTextStyle(color: .white, nativeFontSize: invalid, fontWidth: .expanded)
            XCTAssertNil(GDIRasterTextRenderer.fontDimensions(for: invalidFont, scaleFactor: 1))
            XCTAssertNil(
                GDIRasterTextRenderer.fontDimensions(
                    for: PixelTextStyle(color: .white, nativeFontSize: 16), scaleFactor: invalid))
        }
        XCTAssertNil(
            GDIRasterTextRenderer.fontDimensions(
                for: PixelTextStyle(color: .white, nativeFontSize: Double(Int32.max)), scaleFactor: 2))
    }

    func testGDIInsetsKeepFloorRoundingIncludingNegativeInsets() async throws {
        let rect = try XCTUnwrap(
            GDIRasterTextRenderer.drawRectForInsets(
                EdgeInsets(top: 1.5, leading: -1.5, bottom: 2.5, trailing: -2.5),
                width: 40, height: 30, scaleFactor: 1.5))
        XCTAssertEqual(rect.left, -3)
        XCTAssertEqual(rect.top, 2)
        XCTAssertEqual(rect.right, 44)
        XCTAssertEqual(rect.bottom, 27)
    }

    func testMalformedGDIInsetsDeclineBeforeNativeDrawing() async {
        let invalidValues: [Double] = [
            .nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
        ]
        for invalid in invalidValues {
            for insets in [
                EdgeInsets(top: invalid, leading: 0, bottom: 0, trailing: 0),
                EdgeInsets(top: 0, leading: invalid, bottom: 0, trailing: 0),
                EdgeInsets(top: 0, leading: 0, bottom: invalid, trailing: 0),
                EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: invalid),
            ] {
                XCTAssertNil(
                    GDIRasterTextRenderer.drawRectForInsets(insets, width: 40, height: 30, scaleFactor: 1))
                XCTAssertNil(
                    GDIRasterTextRenderer.rasterize(
                        "Tint", in: Size(width: 40, height: 30),
                        style: PixelTextStyle(color: .white, insets: insets, nativeFontSize: 16), scaleFactor: 1))
            }
        }
        XCTAssertNil(
            GDIRasterTextRenderer.drawRectForInsets(
                EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: Double(Int32.min)),
                width: 40, height: 30, scaleFactor: 1),
            "A valid inset integer must not overflow when subtracted from the raster width")
    }
}
