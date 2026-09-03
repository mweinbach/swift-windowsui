import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Exercises the actual legacy frame kernel, not RenderFrame -> GPUIScene.
/// The private test attachment requires WARP and a real composition swap chain;
/// it creates no HWND and does not Present. Setup, shader, and readback failures
/// throw instead of substituting hardware, CPU pixels, or a routing-only pass.
final class D3D11LegacySeparableBlendTests: XCTestCase {
    private static let size = IntSize(width: 32, height: 32)
    private static let fullRect = Rect(x: 0, y: 0, width: 32, height: 32)
    private static let backdrop = Color(red: 0.2, green: 0.6, blue: 0.8, alpha: 1)
    private static let foreground = Color(red: 0.75, green: 0.4, blue: 0.25, alpha: 1)
    private static let modes: [BlendMode] = [.multiply, .screen, .overlay]

    // These literals follow B(Cs, Cd), not either repository rasterizer.
    // At full alpha the RGB triples are (.15,.24,.20), (.80,.76,.85),
    // and (.30,.52,.70). BGRA8 rounding has a two-byte allowance because
    // the destination is quantized before the shader samples it.
    private static let opaquePixels: [[UInt8]] = [
        [51, 61, 38, 255],
        [217, 194, 204, 255],
        [179, 133, 77, 255],
    ]

    func testOpaqueMultiplyScreenOverlayUseIndependentLiteralPixels() async throws {
        try await MainActor.run {
            try Self.withRenderer { renderer in
                for (index, mode) in Self.modes.enumerated() {
                    let image = try Self.draw(
                        renderer,
                        clear: Self.backdrop,
                        commands: [Self.fill(Self.foreground, mode: mode)])
                    Self.assertPixel(image, x: 16, y: 16, equals: Self.opaquePixels[index])
                    XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct3D11)
                    XCTAssertTrue(renderer.isDirect2DEnabled)
                }
            }
        }
    }

    func testPartialSourceAndDestinationAlphaUsePremultipliedSeparableResult() async throws {
        try await MainActor.run {
            try Self.withRenderer { renderer in
                let destination = Color(red: 0.2, green: 0.6, blue: 0.8, alpha: 0.5)
                let source = Color(red: 0.75, green: 0.4, blue: 0.25, alpha: 0.5)
                // as=ad=.5: premultiplied RGB=(B+Cs+Cd)/4, alpha=.75.
                // A straight-RGB clear would violate this oracle on every mode.
                let expected: [[UInt8]] = [
                    [80, 79, 70, 191],
                    [121, 112, 112, 191],
                    [112, 97, 80, 191],
                ]
                for (index, mode) in Self.modes.enumerated() {
                    let image = try Self.draw(
                        renderer, clear: destination, commands: [Self.fill(source, mode: mode)])
                    Self.assertPixel(image, x: 16, y: 16, equals: expected[index])
                    XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct3D11)
                }
            }
        }
    }

    func testZeroDestinationAlphaDoesNotContributeHiddenRGB() async throws {
        try await MainActor.run {
            try Self.withRenderer { renderer in
                let transparent = Color(red: 0.8, green: 0.2, blue: 0.7, alpha: 0)
                let source = Color(red: 0.75, green: 0.4, blue: 0.25, alpha: 0.5)
                for mode in Self.modes {
                    let image = try Self.draw(
                        renderer, clear: transparent, commands: [Self.fill(source, mode: mode)])
                    // ad=0: RGB=as*Cs=(.375,.20,.125), alpha=.5.
                    Self.assertPixel(image, x: 16, y: 16, equals: [32, 51, 96, 128])
                }
            }
        }
    }

    func testZeroSourceAlphaLeavesTheActualDestinationUnchanged() async throws {
        try await MainActor.run {
            try Self.withRenderer { renderer in
                let source = Color(red: 0.75, green: 0.4, blue: 0.25, alpha: 0)
                for mode in Self.modes {
                    let image = try Self.draw(
                        renderer, clear: Self.backdrop, commands: [Self.fill(source, mode: mode)])
                    Self.assertPixel(image, x: 16, y: 16, equals: [204, 153, 51, 255])
                }
            }
        }
    }

    func testRoundedGeometryAndNestedClipDoNotPaintOutsideTheirIntersection() async throws {
        try await MainActor.run {
            try Self.withRenderer { renderer in
                for (index, mode) in Self.modes.enumerated() {
                    let clipped = FillRectCommand(
                        rect: Rect(x: 2, y: 2, width: 24, height: 24),
                        color: Self.foreground,
                        cornerRadius: 8,
                        clipRect: Rect(x: 3, y: 3, width: 14, height: 21),
                        blendMode: mode)
                    let image = try Self.draw(
                        renderer,
                        clear: Self.backdrop,
                        commands: [
                            .pushClip(
                                ClipCommand(
                                    shape: .rect(
                                        Rect(x: 3, y: 3, width: 15, height: 15), cornerRadius: 0))),
                            .fillRect(clipped),
                            .popClip,
                        ])
                    Self.assertPixel(image, x: 12, y: 12, equals: Self.opaquePixels[index])
                    // Fully excluded corner and hard clip samples do not claim
                    // a numerical antialiasing oracle for fractional edge pixels.
                    Self.assertPixel(image, x: 3, y: 3, equals: [204, 153, 51, 255])
                    Self.assertPixel(image, x: 2, y: 12, equals: [204, 153, 51, 255])
                    Self.assertPixel(image, x: 17, y: 12, equals: [204, 153, 51, 255])
                    Self.assertPixel(image, x: 12, y: 18, equals: [204, 153, 51, 255])
                }
            }
        }
    }

    func testHardStopGradientSegmentsBlendWithTheirOriginalBackdrop() async throws {
        try await MainActor.run {
            try Self.withRenderer { renderer in
                let first = Color(red: 0.75, green: 0.4, blue: 0.25, alpha: 0.5)
                let middle = Color(red: 0.3, green: 0.8, blue: 0.65, alpha: 0.5)
                let last = Color(red: 0.6, green: 0.2, blue: 0.8, alpha: 0.5)
                let gradient = LinearGradient(
                    stops: [
                        GradientStop(color: first, position: 0),
                        GradientStop(color: first, position: 1.0 / 3.0),
                        GradientStop(color: middle, position: 1.0 / 3.0),
                        GradientStop(color: middle, position: 2.0 / 3.0),
                        GradientStop(color: last, position: 2.0 / 3.0),
                        GradientStop(color: last, position: 1),
                    ],
                    axis: .horizontal)
                // ad=1, as=.5: premultiplied RGB=(B+Cd)/2; alpha=1.
                let expected: [[[UInt8]]] = [
                    [[128, 107, 45, 255], [168, 138, 33, 255], [184, 92, 41, 255]],
                    [[210, 173, 128, 255], [221, 194, 82, 255], [224, 163, 112, 255]],
                    [[191, 143, 64, 255], [212, 184, 41, 255], [219, 122, 56, 255]],
                ]
                for (index, mode) in Self.modes.enumerated() {
                    let command = FillRectCommand(
                        rect: Rect(x: 2, y: 2, width: 28, height: 28),
                        color: .clear,
                        gradient: gradient,
                        blendMode: mode)
                    let image = try Self.draw(renderer, clear: Self.backdrop, commands: [.fillRect(command)])
                    Self.assertPixel(image, x: 6, y: 16, equals: expected[index][0])
                    Self.assertPixel(image, x: 16, y: 16, equals: expected[index][1])
                    Self.assertPixel(image, x: 26, y: 16, equals: expected[index][2])
                }
            }
        }
    }

    func testEachBlendSeesEarlierBitmapAndNormalCommandsWithoutLeakingState() async throws {
        try await MainActor.run {
            try Self.withRenderer { renderer in
                let bitmap = BitmapSurface(
                    width: 1,
                    height: 1,
                    bytesPerRow: 4,
                    pixels: Data([77, 179, 26, 255]),
                    format: .bgra8Straight)
                let image = try Self.draw(
                    renderer,
                    clear: Self.backdrop,
                    commands: [
                        Self.fill(Self.foreground, mode: .multiply),
                        .fillRect(
                            FillRectCommand(
                                rect: Rect(x: 2, y: 2, width: 10, height: 10),
                                color: Color(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))),
                        .drawBitmap(
                            DrawBitmapCommand(
                                rect: Rect(x: 20, y: 2, width: 10, height: 10), bitmap: bitmap)),
                        Self.fill(Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5), mode: .screen),
                        .fillRect(
                            FillRectCommand(
                                rect: Rect(x: 2, y: 20, width: 10, height: 10),
                                color: Color(red: 0.1, green: 0.8, blue: 0.9, alpha: 1))),
                        .fillRect(
                            FillRectCommand(
                                rect: Rect(x: 20, y: 20, width: 10, height: 10),
                                color: Color(red: 0.9, green: 0.1, blue: 0.4, alpha: 1),
                                blendMode: .additive)),
                    ])
                // Each expected value uses the destination at its command
                // boundary. Reusing the initial or previous blend's snapshot
                // fails the normal and bitmap regions independently.
                Self.assertPixel(image, x: 6, y: 6, equals: [112, 102, 210, 255], tolerance: 3)
                Self.assertPixel(image, x: 24, y: 6, equals: [144, 198, 55, 255], tolerance: 3)
                Self.assertPixel(image, x: 16, y: 16, equals: [128, 110, 65, 255], tolerance: 3)
                Self.assertPixel(image, x: 6, y: 24, equals: [230, 204, 26, 255])
                // The final additive draw saturates the current premultiplied destination.
                Self.assertPixel(image, x: 24, y: 24, equals: [230, 135, 255, 255])
            }
        }
    }

    func testDirect2DRoutingReturnsAfterSupportedBlendWithoutPermanentDemotion() async throws {
        try await MainActor.run {
            try Self.withRenderer { renderer in
                XCTAssertTrue(renderer.isDirect2DEnabled)
                XCTAssertNil(renderer.lastFrameDrawingPathForTesting)
                let before = try Self.draw(
                    renderer, clear: Self.backdrop, commands: [Self.fill(Self.foreground, mode: .normal)])
                XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct2D)
                Self.assertPixel(before, x: 16, y: 16, equals: [64, 102, 191, 255])

                for (index, mode) in Self.modes.enumerated() {
                    let blended = try Self.draw(
                        renderer, clear: Self.backdrop, commands: [Self.fill(Self.foreground, mode: mode)])
                    XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct3D11)
                    Self.assertPixel(blended, x: 16, y: 16, equals: Self.opaquePixels[index])
                    XCTAssertTrue(renderer.isDirect2DEnabled)
                }

                for mode in [BlendMode.normal, .additive, .normal] {
                    let after = try Self.draw(
                        renderer, clear: Self.backdrop, commands: [Self.fill(Self.foreground, mode: mode)])
                    if mode == .additive {
                        XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct3D11)
                        Self.assertPixel(after, x: 16, y: 16, equals: [255, 255, 242, 255])
                    } else {
                        XCTAssertEqual(renderer.lastFrameDrawingPathForTesting, .direct2D)
                        Self.assertPixel(after, x: 16, y: 16, equals: [64, 102, 191, 255])
                    }
                    XCTAssertTrue(renderer.isDirect2DEnabled)
                }
                // No internal offscreen call has presented a native frame.
                XCTAssertNotEqual(renderer.lastFrameSubmission?.outcome, .submitted)
            }
        }
    }

    @MainActor
    private static func withRenderer(_ body: (D3D11FrameKernel) throws -> Void) throws {
        let renderer = D3D11FrameKernel(configuration: D3D11RendererConfiguration(fallbackClearColor: .clear))
        defer { renderer.detach() }
        try renderer.attachOffscreenForTesting(size: size)
        try body(renderer)
    }

    private static func fill(_ color: Color, mode: BlendMode) -> RenderCommand {
        .fillRect(FillRectCommand(rect: fullRect, color: color, blendMode: mode))
    }

    @MainActor
    private static func draw(
        _ renderer: D3D11FrameKernel,
        clear: Color,
        commands: [RenderCommand]
    ) throws -> BitmapSurface {
        try renderer.renderOffscreenForTesting(frame: RenderFrame(clearColor: clear, commands: commands))
        let image = try renderer.readOffscreenPixelsForTesting()
        XCTAssertEqual(image.width, Int32(size.width))
        XCTAssertEqual(image.height, Int32(size.height))
        XCTAssertEqual(image.format, .bgra8Premultiplied)
        return image
    }

    private static func assertPixel(
        _ image: BitmapSurface,
        x: Int,
        y: Int,
        equals expected: [UInt8],
        tolerance: Int = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let offset = y * Int(image.bytesPerRow) + x * 4
        XCTAssertEqual(expected.count, 4, file: file, line: line)
        XCTAssertLessThan(offset + 3, image.pixels.count, file: file, line: line)
        guard expected.count == 4, offset + 3 < image.pixels.count else { return }
        for channel in 0..<4 {
            let actual = image.pixels[offset + channel]
            XCTAssertLessThanOrEqual(
                abs(Int(actual) - Int(expected[channel])),
                tolerance,
                "Pixel (\(x),\(y)) BGRA channel \(channel): \(actual), expected \(expected[channel])",
                file: file,
                line: line)
        }
    }
}
