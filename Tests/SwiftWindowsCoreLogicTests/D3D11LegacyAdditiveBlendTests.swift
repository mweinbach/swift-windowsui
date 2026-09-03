import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Actual legacy frame execution: strict WARP composition chain, no HWND,
/// no Present, no CPU rendering substitute, and no skip on setup failure.
@MainActor
final class D3D11LegacyAdditiveBlendTests: XCTestCase {
    private let size = IntSize(width: 32, height: 32)
    private let fullRect = Rect(x: 0, y: 0, width: 32, height: 32)
    private let backdrop = Color(red: 0.2, green: 0.6, blue: 0.8, alpha: 1)

    func testOpaqueAdditionUsesIndependentLiteralPixels() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let result = try draw(
            renderer, clear: backdrop, commands: [fill(Color(red: 0.75, green: 0.4, blue: 0.25, alpha: 1))])
        // Premultiplied sum is (.95, 1, 1, 1), in BGRA byte order.
        assertPixel(result, x: 16, y: 16, equals: [255, 255, 242, 255])
        XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct3D11)
        XCTAssertTrue(renderer.isDirect2DEnabled)
    }

    func testPartialAlphaAndSaturationUseIndependentLiteralPixels() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let partial = try draw(
            renderer, clear: Color(red: 0.2, green: 0.6, blue: 0.8, alpha: 0.5),
            commands: [fill(Color(red: 0.75, green: 0.4, blue: 0.25, alpha: 0.25))])
        // (.1,.3,.4,.5) + (.1875,.1,.0625,.25).
        assertPixel(partial, x: 16, y: 16, equals: [118, 102, 73, 191])
        let saturated = try draw(
            renderer, clear: Color(red: 0.75, green: 0.25, blue: 0.4, alpha: 0.8),
            commands: [fill(Color(red: 0.8, green: 0.6, blue: 0.2, alpha: 0.7))])
        // Clamp (.6,.2,.32,.8) + (.56,.42,.14,.7).
        assertPixel(saturated, x: 16, y: 16, equals: [117, 158, 255, 255])
        let transparent = try draw(
            renderer, clear: Color(red: 0.8, green: 0.2, blue: 0.7, alpha: 0),
            commands: [fill(Color(red: 0.75, green: 0.4, blue: 0.25, alpha: 0.5))])
        assertPixel(transparent, x: 16, y: 16, equals: [32, 51, 96, 128])
        XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct3D11)
    }

    func testZeroSourcePreservesActualPremultipliedClearAndUntouchedPixels() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let destination = Color(red: 0.2, green: 0.6, blue: 0.8, alpha: 0.5)
        // A zero-alpha additive command requests the real additive frame route
        // while remaining a no-op. Independently validate its clear conversion.
        let control = try draw(renderer, clear: destination, commands: [fill(.clear)])
        let untouched = pixel(control, x: 0, y: 0)
        let clearInput: [Float] = [
            destination.blue * destination.alpha, destination.green * destination.alpha,
            destination.red * destination.alpha, destination.alpha,
        ]
        for channel in 0..<4 {
            XCTAssertLessThanOrEqual(
                abs(Double(untouched[channel]) - Double(clearInput[channel]) * 255), Double(Float(0.6)))
        }
        let zero = try draw(
            renderer, clear: destination, commands: [fill(Color(red: 0.9, green: 0.7, blue: 0.6, alpha: 0))])
        XCTAssertEqual(zero.pixels, control.pixels)
        let partial = FillRectCommand(
            rect: Rect(x: 4, y: 4, width: 24, height: 24), color: Color(red: 0.5, green: 0.2, blue: 0.8, alpha: 0.5),
            blendMode: .additive)
        let result = try draw(renderer, clear: destination, commands: [.fillRect(partial)])
        assertPixel(result, x: 0, y: 0, equals: untouched, tolerance: 0)
        assertPixel(result, x: 16, y: 16, equals: [204, 102, 89, 255])
    }

    func testRoundedNestedClipCoveragePrecedesClamping() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let rect = Rect(x: 2.25, y: 1.75, width: 25.5, height: 23.5)
        let clip = Rect(x: 3, y: 3, width: 15, height: 15)
        let push = RenderCommand.pushClip(ClipCommand(shape: .rect(clip, cornerRadius: 0)))
        let maskCommand = FillRectCommand(rect: rect, color: .white, cornerRadius: 8, blendMode: .additive)
        let mask = try draw(renderer, clear: .clear, commands: [push, .fillRect(maskCommand), .popClip])
        let destination = Color(red: 0.85, green: 0.2, blue: 0.6, alpha: 1)
        let control = try draw(renderer, clear: destination, commands: [fill(.clear)])
        let source = Color(red: 1, green: 0.5, blue: 0.25, alpha: 0.8)
        let colored = FillRectCommand(rect: rect, color: source, cornerRadius: 8, blendMode: .additive)
        let actual = try draw(renderer, clear: destination, commands: [push, .fillRect(colored), .popClip])
        let initial = pixel(control, x: 0, y: 0).map { Double($0) / 255 }
        let clearInput: [Float] = [destination.blue, destination.green, destination.red, destination.alpha]
        for channel in 0..<4 {
            XCTAssertLessThanOrEqual(
                abs(initial[channel] * 255 - Double(clearInput[channel]) * 255), Double(Float(0.6)))
        }
        let sourceBGRA: [Double] = [0.2, 0.4, 0.8, 0.8]
        var fractional = 0
        for y in 0..<32 {
            for x in 0..<32 {
                let coverage = Double(pixel(mask, x: x, y: y)[3]) / 255
                let expected = zip(sourceBGRA, initial).map { UInt8((min(1, $0.0 * coverage + $0.1) * 255).rounded()) }
                assertPixel(actual, x: x, y: y, equals: expected, tolerance: 3)
                if coverage > 0 && coverage < 1 { fractional += 1 }
            }
        }
        XCTAssertGreaterThan(fractional, 4)
        assertPixel(actual, x: 18, y: 12, equals: pixel(control, x: 18, y: 12), tolerance: 0)
        assertPixel(actual, x: 12, y: 18, equals: pixel(control, x: 12, y: 18), tolerance: 0)
    }

    func testHardStopGradientSegmentsUseOneOriginalDestination() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let first = Color(red: 0.75, green: 0.4, blue: 0.25, alpha: 0.5)
        let middle = Color(red: 0.3, green: 0.8, blue: 0.65, alpha: 0.5)
        let last = Color(red: 0.6, green: 0.2, blue: 0.8, alpha: 0.5)
        let gradient = LinearGradient(
            stops: [
                GradientStop(color: first, position: 0), GradientStop(color: first, position: 1.0 / 3.0),
                GradientStop(color: middle, position: 1.0 / 3.0), GradientStop(color: middle, position: 2.0 / 3.0),
                GradientStop(color: last, position: 2.0 / 3.0), GradientStop(color: last, position: 1),
            ], axis: .horizontal)
        let command = FillRectCommand(
            rect: Rect(x: 2, y: 2, width: 28, height: 28), color: .clear, gradient: gradient, blendMode: .additive)
        let actual = try draw(renderer, clear: backdrop, commands: [.fillRect(command)])
        assertPixel(actual, x: 6, y: 16, equals: [236, 204, 147, 255])
        assertPixel(actual, x: 16, y: 16, equals: [255, 255, 89, 255])
        assertPixel(actual, x: 26, y: 16, equals: [255, 179, 128, 255])
    }

    func testAdditiveReadsEarlierCommandsAndRestoresNormalAndBitmapBlending() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let bitmap = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4, pixels: Data([77, 179, 26, 255]), format: .bgra8Straight)
        let actual = try draw(
            renderer, clear: backdrop,
            commands: [
                fill(Color(red: 0.4, green: 0.2, blue: 0.1, alpha: 0.5)),
                .drawBitmap(DrawBitmapCommand(rect: Rect(x: 2, y: 2, width: 10, height: 10), bitmap: bitmap)),
                fill(Color(red: 0.8, green: 0.8, blue: 0.8, alpha: 0.25)),
                .fillRect(
                    FillRectCommand(
                        rect: Rect(x: 2, y: 20, width: 10, height: 10),
                        color: Color(red: 0.9, green: 0.1, blue: 0.4, alpha: 1))),
                .drawBitmap(DrawBitmapCommand(rect: Rect(x: 20, y: 2, width: 10, height: 10), bitmap: bitmap)),
                .fillRect(
                    FillRectCommand(
                        rect: Rect(x: 20, y: 20, width: 10, height: 10),
                        color: Color(red: 0.5, green: 0.25, blue: 0.75, alpha: 0.5), blendMode: .additive)),
            ])
        assertPixel(actual, x: 6, y: 6, equals: [128, 230, 77, 255])
        assertPixel(actual, x: 24, y: 6, equals: [77, 179, 26, 255], tolerance: 0)
        assertPixel(actual, x: 6, y: 24, equals: [102, 26, 230, 255])
        assertPixel(actual, x: 16, y: 16, equals: [255, 230, 153, 255])
        assertPixel(actual, x: 24, y: 24, equals: [255, 255, 217, 255])
    }

    func testAdditiveFrameRoutingDoesNotDemoteSubsequentDirect2DFrames() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        let source = Color(red: 0.75, green: 0.4, blue: 0.25, alpha: 1)
        let normal = RenderCommand.fillRect(FillRectCommand(rect: fullRect, color: source))
        let before = try draw(renderer, clear: backdrop, commands: [normal])
        XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct2D)
        for _ in 0..<3 {
            let additive = try draw(renderer, clear: backdrop, commands: [fill(source)])
            XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct3D11)
            assertPixel(additive, x: 16, y: 16, equals: [255, 255, 242, 255])
            XCTAssertTrue(renderer.isDirect2DEnabled)
            let after = try draw(renderer, clear: backdrop, commands: [normal])
            XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct2D)
            XCTAssertEqual(after.pixels, before.pixels)
        }
        XCTAssertNotEqual(renderer.lastFrameSubmission?.outcome, .submitted)
    }

    func testSeparableModesClampImportedBackdropColorWhileRetainingEmission() async throws {
        let renderer = try makeRenderer()
        defer { renderer.detach() }
        // Literal BGRA8 oracles for Cs=(.5,.5,.5), as=.5. The first three
        // results are RGBA (.55,.2,.2,.6), (.6,.25,.25,.6), (.6,.2,.2,.6).
        // Clamp only reconstructed Cd inside the blend function; retain raw D.
        let cases: [(pixel: [UInt8], mode: BlendMode, expected: [UInt8])] = [
            ([0, 0, 153, 51], .multiply, [51, 51, 140, 153]),
            ([0, 0, 153, 51], .screen, [64, 64, 153, 153]),
            ([0, 0, 153, 51], .overlay, [51, 51, 153, 153]),
            ([0, 0, 153, 0], .multiply, [64, 64, 140, 128]),
            ([0, 0, 153, 0], .screen, [64, 64, 140, 128]),
            ([0, 0, 153, 0], .overlay, [64, 64, 140, 128]),
            ([0, 0, 51, 102], .multiply, [38, 38, 77, 179]),
            ([0, 0, 51, 102], .screen, [64, 64, 102, 179]),
            ([0, 0, 51, 102], .overlay, [38, 38, 89, 179]),
        ]
        for vector in cases {
            let bitmap = BitmapSurface(
                width: 1, height: 1, bytesPerRow: 4,
                pixels: Data(vector.pixel), format: .bgra8Premultiplied)
            let actual = try draw(
                renderer, clear: .clear,
                commands: [
                    .drawBitmap(DrawBitmapCommand(rect: fullRect, bitmap: bitmap)),
                    .fillRect(
                        FillRectCommand(
                            rect: Rect(x: 8, y: 8, width: 16, height: 16),
                            color: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5),
                            blendMode: vector.mode)),
                ])
            XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct3D11)
            assertPixel(actual, x: 16, y: 16, equals: vector.expected)
            assertPixel(actual, x: 0, y: 0, equals: vector.pixel, tolerance: 0)
        }
    }

    private func makeRenderer() throws -> D3D11FrameKernel {
        let renderer = D3D11FrameKernel(configuration: D3D11RendererConfiguration(fallbackClearColor: .clear))
        do { try renderer.attachOffscreenForTesting(size: size) } catch {
            renderer.detach()
            throw error
        }
        return renderer
    }

    private func fill(_ color: Color) -> RenderCommand {
        .fillRect(FillRectCommand(rect: fullRect, color: color, blendMode: .additive))
    }

    private func draw(_ renderer: D3D11FrameKernel, clear: Color, commands: [RenderCommand]) throws -> BitmapSurface {
        try renderer.renderOffscreenForTesting(frame: RenderFrame(clearColor: clear, commands: commands))
        let image = try renderer.readOffscreenPixelsForTesting()
        XCTAssertEqual(image.width, size.width)
        XCTAssertEqual(image.height, size.height)
        XCTAssertEqual(image.format, .bgra8Premultiplied)
        XCTAssertNotEqual(renderer.lastFrameSubmission?.outcome, .submitted)
        return image
    }

    private func pixel(_ image: BitmapSurface, x: Int, y: Int) -> [UInt8] {
        let offset = y * Int(image.bytesPerRow) + x * 4
        return (0..<4).map { image.pixels[offset + $0] }
    }

    private func assertPixel(
        _ image: BitmapSurface, x: Int, y: Int, equals expected: [UInt8], tolerance: Int = 2,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let actual = pixel(image, x: x, y: y)
        for channel in 0..<4 {
            XCTAssertLessThanOrEqual(
                abs(Int(actual[channel]) - Int(expected[channel])), tolerance,
                "Pixel (\(x),\(y)) BGRA channel \(channel)", file: file, line: line)
        }
    }
}
