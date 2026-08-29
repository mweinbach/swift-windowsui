import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Pins the admitted Windows sampling policy; these are not native SwiftUI
/// reference comparisons. WARP availability remains an explicit test skip.
@MainActor
final class D3D11ImageResizingTests: XCTestCase {
    func testSamplingLayoutsPreserveExistingOffsets() async {
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.stride, 128)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.uvX), 16)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.textureID), 52)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.affineA), 64)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.sourceCapLeft), 80)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.destinationCapLeft), 96)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.centerRepeatX), 112)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.samplingKind), 120)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: \.samplingPadding), 124)

        XCTAssertEqual(MemoryLayout<BitmapUniforms>.size, 80)
        XCTAssertEqual(MemoryLayout<BitmapUniforms>.stride, 80)
        XCTAssertEqual(MemoryLayout<BitmapUniforms>.offset(of: \.rectWidth), 16)
        XCTAssertEqual(MemoryLayout<BitmapUniforms>.offset(of: \.sourceCapLeft), 32)
        XCTAssertEqual(MemoryLayout<BitmapUniforms>.offset(of: \.destinationCapLeft), 48)
        XCTAssertEqual(MemoryLayout<BitmapUniforms>.offset(of: \.centerRepeatX), 64)
        XCTAssertEqual(MemoryLayout<BitmapUniforms>.offset(of: \.samplingKind), 72)
        XCTAssertEqual(MemoryLayout<BitmapUniforms>.offset(of: \.samplingPadding), 76)
    }

    func testFrameCapabilityChoiceIsPerFrameAndPreservesCommandOrder() async {
        let source = bitmap(width: 1, height: 1, pixels: [0, 0, 255, 255])
        let destination = Size(width: 8, height: 4)
        let ordinary = DrawBitmapCommand(rect: Rect(origin: .zero, size: destination), bitmap: source)
        var tiled = ordinary
        tiled.sampling = sampling(for: source, destination: destination)
        let leading = RenderCommand.fillRect(FillRectCommand(rect: ordinary.rect, color: .white))
        let trailing = RenderCommand.fillRect(FillRectCommand(rect: ordinary.rect, color: .black))
        let ordinaryFrame = RenderFrame(commands: [leading, .drawBitmap(ordinary), trailing])
        let tiledFrame = RenderFrame(commands: [leading, .drawBitmap(tiled), trailing])
        let originalOrder = tiledFrame.commands

        XCTAssertTrue(frameSupportsDirect2DImageSampling(ordinaryFrame))
        XCTAssertFalse(frameSupportsDirect2DImageSampling(tiledFrame))
        XCTAssertTrue(frameSupportsDirect2DImageSampling(ordinaryFrame), "The capability choice must not latch")
        XCTAssertEqual(tiledFrame.commands, originalOrder)

        var malformedLegacy = ordinary
        malformedLegacy.sampling.sourceCapLeft = 0.5
        XCTAssertFalse(frameSupportsDirect2DImageSampling(RenderFrame(commands: [.drawBitmap(malformedLegacy)])))
        XCTAssertNotNil(frameBitmapSamplingFailure(malformedLegacy))
    }

    func testScaledFrameBitmapPreservesNewDestinationSamplingAndOtherFields() async {
        let source = bitmap(width: 1, height: 1, pixels: [0, 0, 255, 255])
        let destination = Rect(x: 10.25, y: 5.5, width: 18.8, height: 9.6)
        let descriptor = sampling(for: source, destination: destination.size)
        let command = DrawBitmapCommand(
            rect: destination, bitmap: source, opacity: 0.6,
            clipRect: Rect(x: 11, y: 6, width: 8, height: 4), blendMode: .multiply, sampling: descriptor)
        let result = scaled(bitmap: command, factor: 1.5)

        XCTAssertEqual(result.rect, destination.scaled(by: 1.5))
        XCTAssertEqual(result.clipRect, command.clipRect?.scaled(by: 1.5))
        XCTAssertEqual(result.opacity, command.opacity)
        XCTAssertEqual(result.blendMode, command.blendMode)
        XCTAssertEqual(result.bitmap.contentKey, source.contentKey)
        XCTAssertEqual(result.sampling, descriptor)
        XCTAssertNil(frameBitmapSamplingFailure(result))

        var legacy = command
        legacy.sampling = .legacy
        let legacyResult = scaled(bitmap: legacy, factor: 1.5)
        XCTAssertEqual(legacyResult.rect, Rect(x: 15, y: 8, width: 1, height: 1))
        XCTAssertEqual(legacyResult.sampling, .legacy)
    }

    func testActualExternalBitmapDimensionsValidateSamplingBeforeUpload() async throws {
        let source = bitmap(width: 4, height: 1, pixels: Array(repeating: 255, count: 16))
        let destination = Size(width: 8, height: 2)
        let descriptor = sampling(
            for: source, destination: destination, caps: EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 0))
        var scene = GPUIScene()
        scene.addImage(
            ImagePrimitive(screenX: 0, screenY: 0, screenW: 8, screenH: 2, textureID: 71, sampling: descriptor))
        let renderer = D3D11BatchRenderer()
        renderer.bindImageResource(source, for: 71)
        XCTAssertNoThrow(try renderer.validateBoundImageSampling(in: scene))
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)

        let incompatible = bitmap(width: 2, height: 1, pixels: Array(repeating: 255, count: 8))
        renderer.bindImageResource(incompatible, for: 71)
        XCTAssertThrowsError(try renderer.validateBoundImageSampling(in: scene)) { error in
            let failure = error as? BatchRendererError
            XCTAssertEqual(failure?.operation, "Validate image sampling")
            XCTAssertEqual(failure?.presentationFailureKind, .sceneContent)
        }
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)

        var command = DrawBitmapCommand(rect: Rect(origin: .zero, size: destination), bitmap: incompatible)
        command.sampling = descriptor
        XCTAssertNotNil(frameBitmapSamplingFailure(command))
        command.bitmap = source
        XCTAssertNil(frameBitmapSamplingFailure(command))
    }

    func testCurrentTargetSamplingIsRejectedBeforeReplacementPlanning() async throws {
        let source = bitmap(width: 4, height: 4, pixels: Array(repeating: 255, count: 64))
        let sourceSize = IntSize(width: 4, height: 4)
        let caps = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
        let pass = GPUISceneImageRenderPass(
            textureID: 7, scene: GPUIScene(clearColor: .clear), size: sourceSize, input: .currentTarget)
        for tiled in [false, true] {
            let descriptor = sampling(for: source, destination: Size(width: 8, height: 8), caps: caps, tiled: tiled)
            XCTAssertNil(descriptor.validationFailure(sourceSize: sourceSize))
            var image = ImagePrimitive(
                screenX: 2, screenY: 2, screenW: 4, screenH: 4, textureID: 7, sampling: descriptor)
            var scene = GPUIScene(clearColor: .clear)
            scene.bindImageRenderPass(pass)
            scene.addImage(image)
            scene.finish()
            XCTAssertEqual(scene.layers[0].images.count, 1)
            XCTAssertThrowsError(try D3D11BatchRenderer.makeRenderPlan(for: scene)) { error in
                let failure = error as? BatchRendererError
                XCTAssertEqual(failure?.operation, "Validate scene")
                XCTAssertEqual(failure?.presentationFailureKind, .sceneContent)
                XCTAssertTrue(failure?.details?.contains("require legacy sampling without caps or tiling") == true)
            }

            image.sampling = .legacy
            var recovered = GPUIScene(clearColor: .clear)
            recovered.bindImageRenderPass(pass)
            recovered.addImage(image)
            recovered.finish()
            XCTAssertNoThrow(try D3D11BatchRenderer.makeRenderPlan(for: recovered))
        }
    }

    func testFrameSamplingRejectsInvalidGeometryBeforeUniformUpload() async {
        let source = bitmap(width: 1, height: 1, pixels: [0, 0, 255, 255])
        let descriptor = sampling(for: source, destination: Size(width: 8, height: 4))
        let invalidRects = [
            Rect(x: .infinity, y: 0, width: 8, height: 4),
            Rect(x: 0, y: .nan, width: 8, height: 4),
            Rect(x: 0, y: 0, width: 0, height: 4),
            Rect(x: 0, y: 0, width: -1, height: 4),
            Rect(x: 0, y: 0, width: Double.leastNonzeroMagnitude, height: 4),
            Rect(x: 0, y: 0, width: Double(Float.greatestFiniteMagnitude) * 2, height: 4),
            Rect(x: Double(GPUISceneLimits.maxCoordinate) * 2, y: 0, width: 8, height: 4),
        ]
        for rect in invalidRects {
            let command = DrawBitmapCommand(rect: rect, bitmap: source, sampling: descriptor)
            XCTAssertNotNil(frameBitmapSamplingFailure(command))
        }
        let valid = DrawBitmapCommand(rect: Rect(x: 2, y: 2, width: 8, height: 4), bitmap: source, sampling: descriptor)
        XCTAssertNil(frameBitmapSamplingFailure(valid))
        XCTAssertNotNil(frameBitmapSamplingFailure(scaled(bitmap: valid, factor: .infinity)))
        XCTAssertNotNil(frameBitmapSamplingFailure(scaled(bitmap: valid, factor: Double.greatestFiniteMagnitude)))

        // Placement admission belongs only to the new modes; legacy geometry
        // keeps its established behavior and is not normalized by this slice.
        let legacy = DrawBitmapCommand(rect: invalidRects[0], bitmap: source)
        XCTAssertNil(frameBitmapSamplingFailure(legacy))
    }

    func testTiledPremultipliedSeamsHaveIndependentExpectedPixels() async throws {
        // Transparent blue must never leave a blue fringe around opaque red.
        let straight = bitmap(width: 2, height: 1, pixels: [0, 0, 255, 255, 255, 0, 0, 0])
        let destination = Size(width: 6, height: 2)
        let size = IntSize(width: 12, height: 4)
        for source in [straight, straight.premultipliedAlpha()] {
            for translucentClear in [false, true] {
                let clear: Color = translucentClear ? Color(red: 0, green: 1, blue: 0, alpha: 0.5) : .clear
                let scene = imageScene(
                    source: source, destination: destination,
                    descriptor: sampling(for: source, destination: destination),
                    scale: 2, opacity: 0.5, clear: clear)
                let gpu = try WARPBatchRenderer.render(scene, size: size)
                let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
                assertSamePixels(gpu, cpu)

                // At 2x, each repeat samples 3/4 red, 3/4 red, 1/4 red,
                // 1/4 red. Half opacity is applied once after interpolation.
                for y in 0..<Int(size.height) {
                    for x in 0..<Int(size.width) {
                        let high = x % 4 < 2
                        let expectedRed = high ? 96 : 32
                        let expectedGreen = translucentClear ? (high ? 80 : 112) : 0
                        let expectedAlpha = translucentClear ? (high ? 175 : 143) : expectedRed
                        assertPixel(
                            gpu, x: x, y: y,
                            expected: [0, expectedGreen, expectedRed, expectedAlpha], tolerance: 2)
                    }
                }
            }
        }
    }

    func testCappedStretchAndTileKeepNineRegionsAtFractionalScales() async throws {
        let pixels: [UInt8] = [
            0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255,
            0, 255, 255, 255, 255, 0, 255, 255, 255, 255, 0, 255,
            0, 128, 255, 255, 128, 128, 128, 255, 255, 255, 255, 255,
        ]
        let source = bitmap(width: 3, height: 3, pixels: pixels)
        let destination = Size(width: 7, height: 5)
        let caps = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
        let targetSize = IntSize(width: 16, height: 12)
        for tiled in [false, true] {
            for scale: Float in [1, 1.25, 1.5, 2] {
                let descriptor = sampling(for: source, destination: destination, caps: caps, tiled: tiled)
                var scene = imageScene(
                    source: source, destination: destination, descriptor: descriptor, scale: scale)
                // Eighth-pixel placement keeps cap edges away from exact
                // sample centers while exercising fractional origin and clip.
                var image = scene.layers[0].images[0]
                image.screenX = 0.125
                image.screenY = 0.125
                image.clipX = 0.375
                image.clipY = 0.375
                image.clipWidth = Float(targetSize.width) - 0.75
                image.clipHeight = Float(targetSize.height) - 0.75
                scene = GPUIScene(clearColor: .clear)
                image.textureID = scene.registerImageResource(source)
                scene.addImage(image)
                scene.finish()

                let gpu = try WARPBatchRenderer.render(scene, size: targetSize)
                let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: targetSize).premultipliedAlpha()
                assertSamePixels(gpu, cpu)
                for y in 0..<Int(targetSize.height) {
                    for x in 0..<Int(targetSize.width) {
                        let localX = Float(x) + 0.5 - image.screenX
                        let localY = Float(y) + 0.5 - image.screenY
                        guard localX >= 0, localY >= 0, localX < image.screenW, localY < image.screenH else {
                            continue
                        }
                        let column = localX < scale ? 0 : (localX >= image.screenW - scale ? 2 : 1)
                        let row = localY < scale ? 0 : (localY >= image.screenH - scale ? 2 : 1)
                        let offset = (row * 3 + column) * 4
                        assertPixel(
                            gpu, x: x, y: y,
                            expected: pixels[offset..<(offset + 4)].map(Int.init), tolerance: 2)
                    }
                }
            }
        }
    }

    func testClippingDoesNotRestartCappedTilePhaseOrDropPartialLastTile() async throws {
        // Green and yellow caps enclose alternating red/blue center texels.
        let source = bitmap(
            width: 4, height: 1, pixels: [0, 255, 0, 255, 0, 0, 255, 255, 255, 0, 0, 255, 0, 255, 255, 255])
        let destination = Size(width: 9, height: 1)
        let caps = EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1)
        var scene = GPUIScene(clearColor: .clear)
        let textureID = scene.registerImageResource(source)
        scene.addImage(
            ImagePrimitive(
                screenX: 0, screenY: 0, screenW: 9, screenH: 1,
                clipX: 3.5, clipY: 0, clipWidth: 5.5, clipHeight: 1,
                textureID: textureID, sampling: sampling(for: source, destination: destination, caps: caps)))
        scene.finish()
        let size = IntSize(width: 9, height: 1)
        let gpu = try WARPBatchRenderer.render(scene, size: size)
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        assertSamePixels(gpu, cpu)
        for x in 0..<9 {
            let expected: [Int]
            if x < 3 {
                expected = [0, 0, 0, 0]
            } else if x == 8 {
                expected = [0, 255, 255, 255]
            } else {
                expected = x.isMultiple(of: 2) ? [255, 0, 0, 255] : [0, 0, 255, 255]
            }
            assertPixel(gpu, x: x, y: 0, expected: expected, tolerance: 2)
        }
    }

    func testMaximumTileExtentKeepsOnePrimitiveAndRejectsOverBoundPhase() async throws {
        let source = bitmap(width: 1, height: 1, pixels: [0, 255, 0, 255])
        let destination = Size(width: 4096, height: 4096)
        let descriptor = sampling(for: source, destination: destination)
        XCTAssertNil(descriptor.validationFailure(sourceSize: IntSize(width: 1, height: 1)))
        let scene = imageScene(source: source, destination: destination, descriptor: descriptor)
        XCTAssertEqual(scene.layers[0].images.count, 1)
        XCTAssertEqual(scene.imageResources.count, 1)
        XCTAssertEqual(scene.layers[0].images.count * MemoryLayout<ImagePrimitive>.stride, 128)
        // The target stays tiny; the test never allocates a destination bitmap.
        let size = IntSize(width: 8, height: 8)
        let gpu = try WARPBatchRenderer.render(scene, size: size)
        assertPixel(gpu, x: 7, y: 7, expected: [0, 255, 0, 255], tolerance: 0)

        var excessive = descriptor
        excessive.centerRepeatX = 4097
        XCTAssertNotNil(excessive.validationFailure(sourceSize: IntSize(width: 1, height: 1)))
    }

    func testModeAndCapChangesReuseOriginalTexture() async throws {
        let probe = try makeWARPDevice()
        probe.release()
        let renderer = D3D11BatchRenderer()
        defer { renderer.detach() }
        let size = IntSize(width: 16, height: 8)
        // The device probe succeeded. Shader compilation and pipeline setup
        // failures must fail this test rather than become availability skips.
        try renderer.attachOffscreen(size: size, driver: .warpFirst)
        let source = bitmap(width: 4, height: 1, pixels: Array(repeating: 255, count: 16))
        let destination = Size(width: 9, height: 5)
        let caps = EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1)
        let descriptors: [ImageSamplingDescriptor] = [
            .legacy,
            sampling(for: source, destination: destination, caps: caps, tiled: false),
            sampling(for: source, destination: destination, caps: caps),
            sampling(for: source, destination: destination),
        ]
        var originalTexture: UInt?
        for descriptor in descriptors {
            let scene = imageScene(source: source, destination: destination, descriptor: descriptor)
            renderer.bindResources(for: scene)
            try renderer.render(scene: scene)
            let identity = try XCTUnwrap(renderer.imageTextureIdentityForTesting(for: 0)).texture
            if let originalTexture {
                XCTAssertEqual(identity, originalTexture)
            } else {
                originalTexture = identity
            }
            XCTAssertEqual(renderer.imageTextureUploadsForTesting, 1)
            XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 1)
            XCTAssertEqual(scene.imageResources[0].bitmap.contentKey, source.contentKey)
        }
    }

    private func bitmap(width: Int, height: Int, pixels: [UInt8]) -> BitmapSurface {
        BitmapSurface(width: Int32(width), height: Int32(height), bytesPerRow: Int32(width * 4), pixels: Data(pixels))
    }

    private func sampling(
        for source: BitmapSurface, destination: Size, caps: EdgeInsets = .zero, tiled: Bool = true
    ) -> ImageSamplingDescriptor {
        var descriptor = ImageSamplingDescriptor.legacy
        descriptor.sourceCapLeft = Float(caps.leading) / Float(source.width)
        descriptor.sourceCapTop = Float(caps.top) / Float(source.height)
        descriptor.sourceCapRight = Float(caps.trailing) / Float(source.width)
        descriptor.sourceCapBottom = Float(caps.bottom) / Float(source.height)
        descriptor.destinationCapLeft = Float(caps.leading / destination.width)
        descriptor.destinationCapTop = Float(caps.top / destination.height)
        descriptor.destinationCapRight = Float(caps.trailing / destination.width)
        descriptor.destinationCapBottom = Float(caps.bottom / destination.height)
        let sourceCenter = Size(
            width: Double(source.width) - caps.leading - caps.trailing,
            height: Double(source.height) - caps.top - caps.bottom)
        let destinationCenter = Size(
            width: destination.width - caps.leading - caps.trailing,
            height: destination.height - caps.top - caps.bottom)
        descriptor.centerRepeatX = tiled ? Float(destinationCenter.width / sourceCenter.width) : 1
        descriptor.centerRepeatY = tiled ? Float(destinationCenter.height / sourceCenter.height) : 1
        descriptor.samplingKind = tiled ? 2 : 1
        return descriptor
    }

    private func imageScene(
        source: BitmapSurface, destination: Size, descriptor: ImageSamplingDescriptor,
        scale: Float = 1, opacity: Float = 1, clear: Color = .clear
    ) -> GPUIScene {
        var scene = GPUIScene(clearColor: clear)
        let textureID = scene.registerImageResource(source)
        scene.addImage(
            ImagePrimitive(
                screenX: 0, screenY: 0,
                screenW: Float(destination.width) * scale, screenH: Float(destination.height) * scale,
                opacity: opacity, textureID: textureID, sampling: descriptor))
        scene.finish()
        return scene
    }

    private func assertSamePixels(
        _ actual: BitmapSurface, _ expected: BitmapSurface, file: StaticString = #filePath, line: UInt = #line
    ) {
        let report = comparePixels(actual, expected, tolerance: 2)
        XCTAssertEqual(
            report.matchRatio, 1, accuracy: 0,
            "Sampling mismatch; maximum channel delta: \(report.maxChannelDelta)", file: file, line: line)
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, expected: [Int], tolerance: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        for channel in 0..<4 {
            XCTAssertLessThanOrEqual(
                abs(Int(bitmap.pixels[offset + channel]) - expected[channel]), tolerance,
                "Pixel (\(x),\(y)), BGRA channel \(channel)", file: file, line: line)
        }
    }
}
