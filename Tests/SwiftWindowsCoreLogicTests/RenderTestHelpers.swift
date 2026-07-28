import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsUI
import Testing

@testable import WinSwiftUI

// MARK: - Render to Bitmap

@MainActor
func renderNodeToBitmap(
    _ node: ViewNode,
    size: IntSize = IntSize(width: 100, height: 100),
    clearColor: Color = .black,
    displayScale: Double = 1
) -> BitmapSurface {
    let scene = ScenePainter.paint(
        root: node,
        clearColor: clearColor,
        surfaceSize: Size(width: Double(size.width), height: Double(size.height)),
        displayScale: displayScale
    )
    return GPUIRawSceneRasterizer.rasterize(scene, size: size)
}

@MainActor
func renderViewToBitmap<V: View>(
    _ view: V,
    size: IntSize = IntSize(width: 100, height: 100),
    clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
    displayScale: Double = 1
) -> BitmapSurface {
    let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
        of: view,
        size: size,
        displayScale: displayScale,
        clearColor: clearColor
    )
    return GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
}

// MARK: - Pixel Extraction

extension BitmapSurface {
    func pixelOffset(x: Int, y: Int) -> Int {
        (y * Int(width) + x) * 4
    }

    func colorAt(x: Int, y: Int) -> Color? {
        guard x >= 0, y >= 0, x < Int(width), y < Int(height) else {
            return nil
        }
        let offset = pixelOffset(x: x, y: y)
        guard offset + 3 < pixels.count else { return nil }
        return Color(
            red: Float(pixels[offset + 2]) / 255,
            green: Float(pixels[offset + 1]) / 255,
            blue: Float(pixels[offset]) / 255,
            alpha: Float(pixels[offset + 3]) / 255
        )
    }
}

// MARK: - Pixel Assertions

@MainActor
func assertPixel(
    _ bitmap: BitmapSurface,
    x: Int,
    y: Int,
    color expected: Color,
    tolerance: Float = 2 / 255
) {
    guard let actual = bitmap.colorAt(x: x, y: y) else {
        Issue.record("Coordinate (\(x), \(y)) out of bounds")
        return
    }
    let dr = abs(actual.red - expected.red)
    let dg = abs(actual.green - expected.green)
    let db = abs(actual.blue - expected.blue)
    let da = abs(actual.alpha - expected.alpha)
    #expect(
        dr <= tolerance && dg <= tolerance && db <= tolerance && da <= tolerance,
        "Pixel (\(x), \(y)) expected \(expected) but got \(actual)")
}

@MainActor
func assertRegionColor(
    _ bitmap: BitmapSurface,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    color expected: Color,
    tolerance: Float = 2 / 255
) {
    for py in y..<(y + height) {
        for px in x..<(x + width) {
            assertPixel(bitmap, x: px, y: py, color: expected, tolerance: tolerance)
        }
    }
}

@MainActor
func assertAllPixels(
    _ bitmap: BitmapSurface,
    color expected: Color,
    tolerance: Float = 2 / 255
) {
    let w = Int(bitmap.width)
    let h = Int(bitmap.height)
    for py in 0..<h {
        for px in 0..<w {
            assertPixel(bitmap, x: px, y: py, color: expected, tolerance: tolerance)
        }
    }
}

// MARK: - Reference Images
//
// Deliberately absent. A reference-image harness used to live here —
// `referenceImageURL` / `saveReferenceImage` / `loadReferenceImage` /
// `compareToReference` — with no call sites, and `compareToReference`
// self-healed: on a first run with no baseline it *wrote* the render it
// had just produced into `Tests/SwiftWindowsCoreLogicTests/ReferenceImages/`
// and recorded a pass-with-note. That makes whatever the renderer happened
// to do the baseline, which is the opposite of a reviewed baseline, and it
// wrote generated output into the source tree (AGENTS.md: generated output
// belongs under `artifacts/` or the OS temp directory).
//
// The reviewed-baseline discipline lives in `scripts/gallery-compare.ps1`
// and the golden-hash suites; cross-backend pixel agreement lives in
// `CrossBackendPixelParityTests`. `scripts/check-contracts.ps1` fails the
// build if a `ReferenceImages` directory reappears under `Tests/`.
