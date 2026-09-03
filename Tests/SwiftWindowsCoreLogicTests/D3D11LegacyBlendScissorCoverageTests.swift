import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// A late source-review regression, separate from the original eight frozen tests.
/// Requires the actual legacy WARP composition kernel; setup and readback errors
/// throw. This test does not use a CPU renderer, a normal-mode comparison, or HWND.
final class D3D11LegacyBlendScissorCoverageTests: XCTestCase {
    func testFloatRoundedFillKeepsCoveredPixelsInsideTheActiveScissor() async throws {
        try await MainActor.run {
            let size = IntSize(width: 8, height: 8)
            let renderer = D3D11FrameKernel(
                configuration: D3D11RendererConfiguration(fallbackClearColor: .clear))
            defer { renderer.detach() }
            try renderer.attachOffscreenForTesting(size: size)

            // M = 2^29: Double right = 3, but the shader's Float origin is
            // -M and its Float width is M + 64, so its right endpoint is 64.
            // The old Double geometry intersection copied only scissor x [2,3),
            // then discarded covered pixels at x = 3 and x = 5 in the blend PS.
            let rect = Rect(x: -536_870_943, y: 0, width: 536_870_946, height: 8)
            XCTAssertEqual(rect.maxX, 3)
            XCTAssertEqual(Float(rect.origin.x) + Float(rect.size.width), 64)
            let command = FillRectCommand(
                rect: rect,
                color: Color(red: 0, green: 0, blue: 0, alpha: 1),
                clipRect: Rect(x: 2, y: 2, width: 4, height: 4),
                blendMode: .multiply)
            try renderer.renderOffscreenForTesting(
                frame: RenderFrame(
                    clearColor: Color(red: 1, green: 1, blue: 1, alpha: 1),
                    commands: [.fillRect(command)]))
            let image = try renderer.readOffscreenPixelsForTesting()
            XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct3D11)
            XCTAssertEqual(image.width, 8)
            XCTAssertEqual(image.height, 8)
            XCTAssertEqual(image.format, .bgra8Premultiplied)
            guard image.width == 8, image.height == 8, image.bytesPerRow >= 32,
                image.pixels.count >= Int(image.bytesPerRow) * 8
            else {
                XCTFail("Legacy WARP readback did not contain the complete 8x8 target")
                return
            }

            // Black multiply over opaque white gives RGB = 1 - source coverage,
            // alpha = 1. Nominal Float clipped attributes give localX = M,
            // deltaX = -64, distance = -3.5 at these centers and full coverage.
            // Do not require exact black: retain the conservative coverage >= .5
            // bound, allowing two BGRA8 levels beyond 128 for numerical rounding.
            // This is an independent fixed bound, not native precision evidence.
            for (x, y) in [(3, 3), (5, 3)] {
                let offset = y * Int(image.bytesPerRow) + x * 4
                for channel in 0..<3 {
                    XCTAssertLessThanOrEqual(
                        Int(image.pixels[offset + channel]), 130,
                        "Covered pixel (\(x),\(y)) BGRA channel \(channel) was discarded")
                }
                XCTAssertEqual(image.pixels[offset + 3], 255)
            }

            // These centers are inside the Float geometry but outside one edge
            // of the installed [2,6) x [2,6) scissor. They must stay exact white.
            for (x, y) in [(1, 3), (6, 3), (3, 1), (3, 6)] {
                let offset = y * Int(image.bytesPerRow) + x * 4
                for channel in 0..<4 {
                    XCTAssertEqual(
                        image.pixels[offset + channel], 255,
                        "Outside-scissor pixel (\(x),\(y)) BGRA channel \(channel) changed")
                }
            }
        }
    }
}
