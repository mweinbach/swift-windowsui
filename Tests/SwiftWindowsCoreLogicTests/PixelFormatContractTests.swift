import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// WS-03: the pixel-format and alpha-convention contract.
///
/// `BitmapSurface` used to carry width, height, stride and bytes and
/// nothing else, so every consumer guessed. The CPU rasterizer writes
/// straight-alpha BGRA; the DirectWrite/GDI text path writes *premultiplied*
/// BGRA; the batch renderer uploaded both as `R8G8B8A8_UNORM` and blended
/// them as if premultiplied. This suite pins the contract that replaced the
/// guessing:
///
/// - the surface names its own channel order and alpha mode,
/// - a surface whose buffer is shorter than its geometry is rejected rather
///   than uploaded,
/// - and the GPU and the CPU reference agree on the resulting pixels.
@MainActor
final class PixelFormatContractTests: XCTestCase {

    // MARK: - The Named Convention

    /// Names the default so a consumer cannot silently re-assume a
    /// different one: changing this line means changing every consumer.
    func testDefaultFormatIsStraightAlphaBGRA() async throws {
        let surface = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 0, 0]))
        XCTAssertEqual(surface.format, .bgra8Straight)
        XCTAssertEqual(surface.format.channelOrder, .bgra)
        XCTAssertEqual(surface.format.alphaMode, .straight)
    }

    /// The CPU rasterizer is the declared reference renderer, so its output
    /// convention is part of the contract.
    func testRasterizerOutputIsStraightAlpha() async throws {
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 4, height: 4,
                startR: 1, startG: 0, startB: 0, startA: 1,
                endR: 1, endG: 0, endB: 0, endA: 1
            )
        )
        scene.finish()

        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 4, height: 4))
        XCTAssertEqual(bitmap.format, .bgra8Straight)
        // Pure red in BGRA is (0, 0, 255, 255).
        XCTAssertEqual(Array(bitmap.pixels[0..<4]), [0, 0, 255, 255])
    }

    // MARK: - Alpha Conversions

    func testPremultiplyThenUnpremultiplyRoundTrips() async throws {
        // 50 % alpha white: straight (255, 255, 255, 128).
        let straight = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4, pixels: Data([255, 255, 255, 128]))
        let premultiplied = straight.premultipliedAlpha()

        XCTAssertEqual(premultiplied.format.alphaMode, .premultiplied)
        XCTAssertEqual(Array(premultiplied.pixels[0..<4]), [128, 128, 128, 128])

        let roundTripped = premultiplied.straightAlpha()
        XCTAssertEqual(roundTripped.format.alphaMode, .straight)
        for channel in 0..<3 {
            XCTAssertEqual(
                Int(roundTripped.pixels[channel]), 255, accuracy: 2,
                "channel \(channel) lost more than rounding in the round trip")
        }
        XCTAssertEqual(roundTripped.pixels[3], 128)
    }

    /// Converting is a no-op for opaque pixels, which is what keeps the
    /// per-upload cost off the common path.
    func testOpaqueSurfaceConvertsWithoutCopying() async throws {
        let opaque = BitmapSurface(
            width: 2, height: 1, bytesPerRow: 8, pixels: Data([10, 20, 30, 255, 40, 50, 60, 255]))
        let premultiplied = opaque.premultipliedAlpha()
        XCTAssertEqual(premultiplied.pixels, opaque.pixels)
        XCTAssertEqual(premultiplied.format.alphaMode, .premultiplied)
    }

    /// "Without copying" has to mean *without copying*, not "copies and then
    /// discards the copy". The conversion used to allocate a full duplicate
    /// of the buffer before it could discover that every pixel was opaque,
    /// which put a full-surface copy on the main thread for every image
    /// upload of every frame. Storage identity is the observable difference.
    func testOpaqueConversionSharesTheSourceBufferRatherThanReallocating() async throws {
        let opaque = makeOpaqueSurface(width: 32, height: 32)
        let premultiplied = opaque.premultipliedAlpha()

        XCTAssertTrue(
            sharesBuffer(premultiplied.pixels, opaque.pixels),
            "An all-opaque surface must be relabelled in place, not copied")
        XCTAssertFalse(
            sharesBuffer(opaque.pixels, makeOpaqueSurface(width: 32, height: 32).pixels),
            "Two separately built surfaces with equal bytes are not the same buffer — "
                + "otherwise the assertion above proves nothing")
    }

    /// One translucent pixel is enough to make the conversion real, and the
    /// result must then be a different buffer with converted bytes.
    func testTranslucentSurfaceConversionProducesANewBuffer() async throws {
        var pixels = makeOpaqueSurface(width: 32, height: 32).pixels
        pixels[pixels.count - 1] = 128
        let translucent = BitmapSurface(width: 32, height: 32, bytesPerRow: 128, pixels: pixels)

        let premultiplied = translucent.premultipliedAlpha()
        XCTAssertFalse(sharesBuffer(premultiplied.pixels, translucent.pixels))
        XCTAssertEqual(premultiplied.format.alphaMode, .premultiplied)
        // Last pixel: straight BGRA (31, 31, 200, 128) premultiplies to
        // (value * 128 + 127) / 255 per colour channel.
        let tail = Array(premultiplied.pixels[(premultiplied.pixels.count - 4)...])
        XCTAssertEqual(tail, [16, 16, 100, 128])
        // Every opaque pixel is untouched by the conversion.
        XCTAssertEqual(
            Array(premultiplied.pixels[0..<4]), Array(translucent.pixels[0..<4]),
            "Opaque pixels are identical under both conventions and must not be rewritten")
    }

    /// `contentKey` is what keeps a frame-stable image from being
    /// re-converted and re-uploaded every frame, so it has to match only
    /// for genuinely the same content.
    func testContentKeyMatchesOnlyForTheSameContent() async throws {
        let surface = makeOpaqueSurface(width: 32, height: 32)
        var copy = surface
        XCTAssertEqual(
            surface.contentKey, copy.contentKey,
            "A copy of the same surface is the same upload")
        XCTAssertNotEqual(
            surface.contentKey, makeOpaqueSurface(width: 32, height: 32).contentKey,
            "An independently built buffer is a different upload, even byte for byte")

        var relabelled = surface
        relabelled.format = .bgra8Premultiplied
        XCTAssertNotEqual(
            surface.contentKey, relabelled.contentKey,
            "Same bytes under a different convention are a different upload")

        var resized = surface
        resized.width = 16
        XCTAssertNotEqual(surface.contentKey, resized.contentKey)

        // Writing through `pixels` — including in place — re-mints the
        // token, so a cached texture is never mistaken for the new bytes.
        copy.pixels[0] = ~copy.pixels[0]
        XCTAssertNotEqual(surface.contentKey, copy.contentKey)

        // The token is content identity, not object identity: it survives
        // buffers too small to have a stable address.
        let tiny = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([1, 2, 3, 255]))
        XCTAssertEqual(tiny.contentKey, tiny.contentKey)
    }

    /// A surface whose stride is wider than its pixels must not be judged
    /// by its padding bytes, which are zero and would read as translucent.
    func testRowPaddingDoesNotCountAsTranslucency() async throws {
        // 2 pixels per row, 16-byte stride: 8 bytes of pixels, 8 of padding.
        var pixels = Data()
        for _ in 0..<2 {
            pixels.append(contentsOf: [10, 20, 30, 255, 40, 50, 60, 255])
            pixels.append(contentsOf: [UInt8](repeating: 0, count: 8))
        }
        let padded = BitmapSurface(width: 2, height: 2, bytesPerRow: 16, pixels: pixels)
        XCTAssertEqual(padded.premultipliedAlpha().pixels, padded.pixels)
    }

    /// Byte-buffer identity, which is what "converts without copying"
    /// actually means. `Data` compares by value, so equality cannot tell a
    /// shared buffer from a duplicate with the same contents.
    private func sharesBuffer(_ lhs: Data, _ rhs: Data) -> Bool {
        lhs.withUnsafeBytes { left in
            rhs.withUnsafeBytes { right in
                left.baseAddress != nil && left.baseAddress == right.baseAddress
            }
        }
    }

    private func makeOpaqueSurface(width: Int, height: Int) -> BitmapSurface {
        var pixels = Data()
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(contentsOf: [UInt8(x % 256), UInt8(y % 256), 200, 255])
            }
        }
        return BitmapSurface(
            width: Int32(width), height: Int32(height), bytesPerRow: Int32(width * 4), pixels: pixels)
    }

    func testFullyTransparentPixelsPremultiplyToZero() async throws {
        let straight = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4, pixels: Data([200, 180, 160, 0]))
        XCTAssertEqual(Array(straight.premultipliedAlpha().pixels[0..<4]), [0, 0, 0, 0])
    }

    /// `pixelColor` reports the straight-alpha colour whichever way the
    /// bytes are stored, so assertions written against the rasterizer keep
    /// working on a premultiplied surface.
    func testPixelColorUnpremultiplies() async throws {
        var premultiplied = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 128, 128]))
        premultiplied.format = .bgra8Premultiplied

        let color = try XCTUnwrap(premultiplied.pixelColor(atX: 0, y: 0))
        XCTAssertEqual(color.red, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.green, 0.0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0.0, accuracy: 0.01)
        XCTAssertEqual(color.alpha, 128.0 / 255.0, accuracy: 0.01)
    }

    // MARK: - Validation

    func testTruncatedPixelBufferIsRejected() async throws {
        let truncated = BitmapSurface(width: 8, height: 8, bytesPerRow: 32, pixels: Data(count: 16))
        XCTAssertThrowsError(try truncated.validate()) { error in
            XCTAssertEqual(
                error as? BitmapSurfaceError,
                .pixelBufferTooSmall(available: 16, required: 256))
        }
    }

    func testStrideNarrowerThanARowIsRejected() async throws {
        let narrow = BitmapSurface(width: 8, height: 2, bytesPerRow: 16, pixels: Data(count: 256))
        XCTAssertThrowsError(try narrow.validate()) { error in
            XCTAssertEqual(error as? BitmapSurfaceError, .bytesPerRowTooSmall(bytesPerRow: 16, minimum: 32))
        }
    }

    func testNonPositiveDimensionsAreRejected() async throws {
        let empty = BitmapSurface(width: 0, height: 4, bytesPerRow: 0, pixels: Data())
        XCTAssertThrowsError(try empty.validate()) { error in
            XCTAssertEqual(error as? BitmapSurfaceError, .nonPositiveDimensions(width: 0, height: 4))
        }
        let negative = BitmapSurface(width: 4, height: -1, bytesPerRow: 16, pixels: Data(count: 64))
        XCTAssertThrowsError(try negative.validate())
    }

    /// Padded strides are legal — GDI DIBs align rows — as long as the
    /// buffer actually carries them.
    func testPaddedStrideIsAccepted() async throws {
        let padded = BitmapSurface(width: 3, height: 2, bytesPerRow: 16, pixels: Data(count: 32))
        XCTAssertNoThrow(try padded.validate())
        XCTAssertEqual(padded.describedByteCount, 32)
    }

    /// The upload path must reject a malformed surface rather than hand its
    /// short buffer to `CreateTexture2D`, which would read off the heap.
    func testMalformedSurfaceIsRejectedByTheUploadRatherThanRead() async throws {
        let renderer = try WARPBatchRenderer.shared(size: Self.surfaceSize)

        var scene = GPUIScene(clearColor: Self.clearColor)
        scene.bindImageResource(
            BitmapSurface(width: 16, height: 16, bytesPerRow: 64, pixels: Data(count: 32)), for: 4001)
        scene.addImage(
            ImagePrimitive(
                screenX: 0, screenY: 0, screenW: 16, screenH: 16,
                uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                opacity: 1,
                textureID: 4001
            )
        )
        scene.finish()

        renderer.bindResources(for: scene)
        XCTAssertThrowsError(try renderer.render(scene: scene)) { error in
            let described = String(describing: error)
            XCTAssertTrue(
                described.contains("holds 32 bytes"),
                "expected a typed pixel-buffer error, got: \(described)")
        }
    }

    // MARK: - Channel Order Through the GPU

    private static let surfaceSize = IntSize(width: 16, height: 16)
    /// Opaque black: with an opaque destination the premultiplied GPU
    /// output and the CPU rasterizer's straight-alpha compositing produce
    /// identical bytes, so any diff is channel order or alpha handling.
    private static let clearColor = Color(red: 0, green: 0, blue: 0, alpha: 1)

    private func renderThroughBothBackends(
        _ build: (inout GPUIScene) -> Void
    ) throws -> (gpu: BitmapSurface, cpu: BitmapSurface) {
        var scene = GPUIScene(clearColor: Self.clearColor)
        build(&scene)
        scene.finish()

        let gpu = try WARPBatchRenderer.render(scene, size: Self.surfaceSize)
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surfaceSize)
        return (gpu, cpu)
    }

    /// A 1×1 surface holding pure red *in BGRA* must come back red, not
    /// blue. This is the whole of the R8G8B8A8/B8G8R8A8 defect in one
    /// assertion.
    func testPureRedImageReadsBackRed() async throws {
        let red = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 255, 255]))
        let (gpu, cpu) = try renderThroughBothBackends { scene in
            scene.bindImageResource(red, for: 4101)
            scene.addImage(
                ImagePrimitive(
                    screenX: 0, screenY: 0, screenW: 16, screenH: 16,
                    uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                    opacity: 1,
                    textureID: 4101
                )
            )
        }

        let center = try XCTUnwrap(gpu.pixelColor(atX: 8, y: 8))
        XCTAssertEqual(center.red, 1, accuracy: 0.02, "image red channel arrived in the wrong slot")
        XCTAssertEqual(center.green, 0, accuracy: 0.02)
        XCTAssertEqual(center.blue, 0, accuracy: 0.02)

        let report = comparePixels(gpu, cpu, tolerance: 1)
        XCTAssertEqual(report.matchRatio, 1.0, "GPU and CPU disagree: max delta \(report.maxChannelDelta)")
    }

    /// Half-transparent white over black is ~128 per channel under a
    /// correct premultiplied composite, and 255 under the old
    /// straight-alpha-into-premultiplied-blend bug.
    func testHalfTransparentWhiteCompositesToMidGray() async throws {
        let translucentWhite = BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4, pixels: Data([255, 255, 255, 128]))
        let (gpu, cpu) = try renderThroughBothBackends { scene in
            scene.bindImageResource(translucentWhite, for: 4102)
            scene.addImage(
                ImagePrimitive(
                    screenX: 0, screenY: 0, screenW: 16, screenH: 16,
                    uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                    opacity: 1,
                    textureID: 4102
                )
            )
        }

        for channel in 0..<3 {
            XCTAssertEqual(
                Int(gpu.pixels[8 * Int(gpu.bytesPerRow) + 8 * 4 + channel]), 128, accuracy: 3,
                "channel \(channel) is not a half-strength composite")
        }

        let report = comparePixels(gpu, cpu, tolerance: 2)
        XCTAssertEqual(report.matchRatio, 1.0, "GPU and CPU disagree: max delta \(report.maxChannelDelta)")
    }

    /// A surface tagged premultiplied (what the DirectWrite/GDI text path
    /// produces, and what `Controls.icon` feeds into the image pipeline)
    /// must not be premultiplied a second time — on either backend.
    func testPremultipliedSurfaceIsNotMultipliedTwice() async throws {
        // Straight (255, 255, 255, 128) already premultiplied.
        var icon = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([128, 128, 128, 128]))
        icon.format = .bgra8Premultiplied

        let (gpu, cpu) = try renderThroughBothBackends { scene in
            scene.bindImageResource(icon, for: 4103)
            scene.addImage(
                ImagePrimitive(
                    screenX: 0, screenY: 0, screenW: 16, screenH: 16,
                    uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                    opacity: 1,
                    textureID: 4103
                )
            )
        }

        for channel in 0..<3 {
            XCTAssertEqual(
                Int(gpu.pixels[8 * Int(gpu.bytesPerRow) + 8 * 4 + channel]), 128, accuracy: 3,
                "channel \(channel) was premultiplied twice")
        }

        let report = comparePixels(gpu, cpu, tolerance: 2)
        XCTAssertEqual(report.matchRatio, 1.0, "GPU and CPU disagree: max delta \(report.maxChannelDelta)")
    }

    /// `PathPrimitive` reaches the GPU through the same texture upload, so
    /// the fill colour has to survive it: a red fill must not come back
    /// blue, and its antialiased edge must not halo.
    func testPathFillKeepsItsColorThroughTheTextureUpload() async throws {
        let (gpu, cpu) = try renderThroughBothBackends { scene in
            scene.addPath(
                PathPrimitive(
                    elements: [
                        .moveTo(Point(x: 2, y: 2)),
                        .lineTo(Point(x: 14, y: 2)),
                        .lineTo(Point(x: 14, y: 14)),
                        .lineTo(Point(x: 2, y: 14)),
                        .close,
                    ],
                    bounds: Rect(x: 2, y: 2, width: 12, height: 12),
                    fillColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
                ),
                toLayer: 0
            )
        }

        let center = try XCTUnwrap(gpu.pixelColor(atX: 8, y: 8))
        XCTAssertEqual(center.red, 1, accuracy: 0.02, "path fill red channel arrived in the wrong slot")
        XCTAssertEqual(center.blue, 0, accuracy: 0.02)

        let report = comparePixels(gpu, cpu, tolerance: 2)
        XCTAssertGreaterThanOrEqual(
            report.matchRatio, 0.995,
            "path texture parity: max delta \(report.maxChannelDelta)")
    }
}
