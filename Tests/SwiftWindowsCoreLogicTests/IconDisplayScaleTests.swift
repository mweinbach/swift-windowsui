import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Icon rasterization must honor the display scale: on >100% DPI displays the
/// icon bitmap carries the physical pixel count while the node's preferred
/// size stays in logical points. Scale 1 (the deterministic screenshot path)
/// must stay byte-identical to the pre-DPI-aware behavior.
final class IconDisplayScaleTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run {
            NativeTextRenderer.defaultIconDisplayScale = 1
        }
        try await super.tearDown()
    }

    func testIconRasterizesAtRequestedDisplayScale() async throws {
        try await MainActor.run {
            let logicalSize = Size(width: 24, height: 24)
            let scale1Node = Controls.icon(.search, preferredSize: logicalSize, displayScale: 1)
            let scale2Node = Controls.icon(.search, preferredSize: logicalSize, displayScale: 2)

            let scale1Bitmap = try XCTUnwrap(scale1Node.bitmapSurface, "scale-1 icon must rasterize")
            let scale2Bitmap = try XCTUnwrap(scale2Node.bitmapSurface, "scale-2 icon must rasterize")

            // Higher display scale -> proportionally larger bitmap.
            XCTAssertGreaterThan(scale2Bitmap.width, scale1Bitmap.width)
            XCTAssertGreaterThan(scale2Bitmap.height, scale1Bitmap.height)
            XCTAssertEqual(
                Double(scale2Bitmap.width) / Double(scale1Bitmap.width), 2, accuracy: 0.35,
                "scale-2 bitmap should be about twice as wide")
            XCTAssertEqual(
                Double(scale2Bitmap.height) / Double(scale1Bitmap.height), 2, accuracy: 0.35,
                "scale-2 bitmap should be about twice as tall")
            XCTAssertTrue(
                scale2Bitmap.pixels.contains { $0 != 0 },
                "scale-2 bitmap must contain visible pixels")

            // The node stays in logical points regardless of raster scale.
            XCTAssertEqual(scale1Node.preferredSize, logicalSize)
            XCTAssertEqual(scale2Node.preferredSize, logicalSize)
        }
    }

    func testIconScaleOneIsByteIdenticalToDefaultRasterization() async throws {
        try await MainActor.run {
            NativeTextRenderer.defaultIconDisplayScale = 1

            // Default call (host-set scale, 1 for tools/screenshots) versus an
            // explicit scale-1 call: the scale-1 code path must not drift.
            let defaultNode = Controls.icon(.search, preferredSize: Size(width: 24, height: 24))
            let explicitNode = Controls.icon(
                .search, preferredSize: Size(width: 24, height: 24), displayScale: 1)

            let defaultBitmap = try XCTUnwrap(defaultNode.bitmapSurface)
            let explicitBitmap = try XCTUnwrap(explicitNode.bitmapSurface)
            XCTAssertEqual(defaultBitmap.width, explicitBitmap.width)
            XCTAssertEqual(defaultBitmap.height, explicitBitmap.height)
            XCTAssertEqual(
                defaultBitmap.pixels, explicitBitmap.pixels,
                "scale-1 icon rasterization must be byte-identical")

            // Rasterization is deterministic: repeated calls agree exactly.
            let repeatNode = Controls.icon(.search, preferredSize: Size(width: 24, height: 24))
            XCTAssertEqual(repeatNode.bitmapSurface?.pixels, defaultBitmap.pixels)
        }
    }

    func testIconDefaultDisplayScaleGlobalDrivesUnspecifiedCalls() async throws {
        try await MainActor.run {
            NativeTextRenderer.defaultIconDisplayScale = 2
            defer { NativeTextRenderer.defaultIconDisplayScale = 1 }

            let hostedNode = Controls.icon(.search, preferredSize: Size(width: 24, height: 24))
            let explicitNode = Controls.icon(
                .search, preferredSize: Size(width: 24, height: 24), displayScale: 2)

            let hostedBitmap = try XCTUnwrap(
                hostedNode.bitmapSurface, "host-set display scale must drive icon rasterization")
            let explicitBitmap = try XCTUnwrap(explicitNode.bitmapSurface)
            XCTAssertEqual(hostedBitmap.width, explicitBitmap.width)
            XCTAssertEqual(hostedBitmap.height, explicitBitmap.height)
            XCTAssertEqual(
                hostedBitmap.pixels, explicitBitmap.pixels,
                "unspecified displayScale must behave like an explicit host-set scale")
            XCTAssertEqual(hostedNode.preferredSize, Size(width: 24, height: 24))
        }
    }
}
