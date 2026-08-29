import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics

/// Windows sampling contracts, not native SwiftUI parity evidence.
@MainActor
final class ImageSamplingPlanTests: XCTestCase {
    func testSamplingDescriptorLayoutPreservesEveryExistingImageFieldOffset() async {
        XCTAssertEqual(MemoryLayout<ImageSamplingDescriptor>.size, 48)
        XCTAssertEqual(MemoryLayout<ImageSamplingDescriptor>.stride, 48)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.size, 128)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.stride, 128)
        let imageOffsets: [(PartialKeyPath<ImagePrimitive>, Int)] = [
            (\.screenX, 0), (\.screenY, 4), (\.screenW, 8), (\.screenH, 12),
            (\.uvX, 16), (\.uvY, 20), (\.uvW, 24), (\.uvH, 28),
            (\.opacity, 32), (\.clipX, 36), (\.clipY, 40),
            (\.clipWidth, 44), (\.clipHeight, 48), (\.textureID, 52),
            (\.clipCornerRadius, 56), (\.rotationRadians, 60),
            (\.affineA, 64), (\.affineB, 68), (\.affineC, 72), (\.affineD, 76),
            (\.sourceCapLeft, 80), (\.sourceCapTop, 84),
            (\.sourceCapRight, 88), (\.sourceCapBottom, 92),
            (\.destinationCapLeft, 96), (\.destinationCapTop, 100),
            (\.destinationCapRight, 104), (\.destinationCapBottom, 108),
            (\.centerRepeatX, 112), (\.centerRepeatY, 116),
            (\.samplingKind, 120), (\.samplingPadding, 124),
        ]
        for (field, offset) in imageOffsets {
            XCTAssertEqual(MemoryLayout<ImagePrimitive>.offset(of: field), offset)
        }
        let samplingOffsets: [(PartialKeyPath<ImageSamplingDescriptor>, Int)] = [
            (\.sourceCapLeft, 0), (\.sourceCapTop, 4),
            (\.sourceCapRight, 8), (\.sourceCapBottom, 12),
            (\.destinationCapLeft, 16), (\.destinationCapTop, 20),
            (\.destinationCapRight, 24), (\.destinationCapBottom, 28),
            (\.centerRepeatX, 32), (\.centerRepeatY, 36),
            (\.samplingKind, 40), (\.samplingPadding, 44),
        ]
        for (field, offset) in samplingOffsets {
            XCTAssertEqual(MemoryLayout<ImageSamplingDescriptor>.offset(of: field), offset)
        }
    }

    func testZeroCapStretchAndExistingProducersKeepLegacySampling() async throws {
        let sampling = try plan(
            source: IntSize(width: 4, height: 3), destination: Size(width: 22, height: 7), mode: .stretch)
        XCTAssertEqual(sampling, .legacy)
        XCTAssertTrue(sampling.isLegacy)
        XCTAssertEqual(sampling.samplingKind, 0)
        XCTAssertEqual(sampling.centerRepeatX, 1)
        XCTAssertEqual(sampling.centerRepeatY, 1)
        XCTAssertEqual(ImagePrimitive().sampling, .legacy)
        let source = solidPixel()
        XCTAssertEqual(DrawBitmapCommand(rect: Rect(x: 0, y: 0, width: 4, height: 3), bitmap: source).sampling, .legacy)
        // Legacy cropped UVs remain valid; the new modes alone require the full source.
        XCTAssertNil(sampling.validationFailure(sourceSize: IntSize(width: 4, height: 3), uvX: 0.25, uvW: 0.5))
    }

    func testAsymmetricCapsResolveSourceAndDestinationFractionsIndependently() async throws {
        let source = IntSize(width: 8, height: 6)
        let destination = Size(width: 13, height: 10)
        let caps = EdgeInsets(top: 1, leading: 2, bottom: 2, trailing: 1)
        for mode in [ImageSamplingMode.stretch, .tile] {
            let sampling = try plan(source: source, destination: destination, caps: caps, mode: mode)
            XCTAssertFalse(sampling.isLegacy)
            XCTAssertEqual(sampling.sourceCapLeft, 2 / Float(8))
            XCTAssertEqual(sampling.sourceCapTop, 1 / Float(6))
            XCTAssertEqual(sampling.sourceCapRight, 1 / Float(8))
            XCTAssertEqual(sampling.sourceCapBottom, 2 / Float(6))
            XCTAssertEqual(sampling.destinationCapLeft, 2 / Float(13))
            XCTAssertEqual(sampling.destinationCapTop, 1 / Float(10))
            XCTAssertEqual(sampling.destinationCapRight, 1 / Float(13))
            XCTAssertEqual(sampling.destinationCapBottom, 2 / Float(10))
            XCTAssertEqual(sampling.samplingKind, mode == .stretch ? 1 : 2)
            XCTAssertEqual(sampling.centerRepeatX, mode == .stretch ? 1 : 2)
            XCTAssertEqual(sampling.centerRepeatY, mode == .stretch ? 1 : 7 / Float(3))
            XCTAssertNil(sampling.validationFailure(sourceSize: source))
        }
    }

    func testStretchMapsAllNineAsymmetricRegionsWithoutMixingTheirTexels() async throws {
        let source = IntSize(width: 8, height: 8)
        let sampling = try plan(
            source: source, destination: Size(width: 16, height: 16),
            caps: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 1), mode: .stretch)
        let kernel = try XCTUnwrap(ImageSamplingKernel(sampling: sampling, sourceSize: source))
        // Destination positions and literal source taps independently describe
        // left/center/right crossed with top/center/bottom.
        let horizontal: [(Float, Int, Int, Double)] = [(0.5, 0, 1, 0), (8.5, 4, 5, 0), (15.5, 7, 7, 0)]
        let vertical: [(Float, Int, Int, Double)] = [(0.5, 0, 0, 0), (7, 2, 3, 0.5), (14.5, 6, 7, 0)]
        for x in horizontal {
            for y in vertical {
                let taps = kernel.taps(unitX: x.0 / 16, unitY: y.0 / 16)
                assertTap(taps.x, low: x.1, high: x.2, fraction: x.3)
                assertTap(taps.y, low: y.1, high: y.2, fraction: y.3)
            }
        }
    }

    func testStretchClampsBothTapsInsideTheSelectedCapOrCenterBand() async throws {
        let source = IntSize(width: 8, height: 1)
        let sampling = try plan(
            source: source, destination: Size(width: 16, height: 1),
            caps: EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 1), mode: .stretch)
        let kernel = try XCTUnwrap(ImageSamplingKernel(sampling: sampling, sourceSize: source))
        assertTap(kernel.taps(unitX: 1.75 / 16, unitY: 0.5).x, low: 1, high: 1, fraction: 0.25)
        assertTap(kernel.taps(unitX: 2 / 16, unitY: 0.5).x, low: 2, high: 2, fraction: 0.5)
        assertTap(kernel.taps(unitX: 15 / 16, unitY: 0.5).x, low: 7, high: 7, fraction: 0.5)
    }

    func testTileSeamsWrapWithinTheCenterAndDoNotSampleEitherCap() async throws {
        let source = IntSize(width: 8, height: 8)
        let sampling = try plan(
            source: source, destination: Size(width: 16, height: 16),
            caps: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 2), mode: .tile)
        let kernel = try XCTUnwrap(ImageSamplingKernel(sampling: sampling, sourceSize: source))
        for x in [Float(2), 6, 10] {
            for y in [Float(1), 5, 9] {
                let taps = kernel.taps(unitX: x / 16, unitY: y / 16)
                assertTap(taps.x, low: 5, high: 2, fraction: 0.5)
                assertTap(taps.y, low: 4, high: 1, fraction: 0.5)
            }
        }
        let trailing = kernel.taps(unitX: 14 / 16, unitY: 13 / 16)
        assertTap(trailing.x, low: 6, high: 6, fraction: 0.5)
        assertTap(trailing.y, low: 5, high: 5, fraction: 0.5)
    }

    func testTileSmallerThanItsSourceCropsTheFirstTileInsteadOfShrinkingIt() async throws {
        let source = IntSize(width: 4, height: 4)
        let sampling = try plan(source: source, destination: Size(width: 1, height: 1))
        XCTAssertEqual(sampling.centerRepeatX, 0.25)
        XCTAssertEqual(sampling.centerRepeatY, 0.25)
        let kernel = try XCTUnwrap(ImageSamplingKernel(sampling: sampling, sourceSize: source))
        let taps = kernel.taps(unitX: 0.5, unitY: 0.5)
        assertTap(taps.x, low: 0, high: 1, fraction: 0)
        assertTap(taps.y, low: 0, high: 1, fraction: 0)
    }

    func testNonlegacyPlansRejectEmptyNegativeAndOversizedSources() async {
        for source in [
            IntSize(width: 0, height: 1), IntSize(width: 1, height: 0),
            IntSize(width: -1, height: 1), IntSize(width: 1, height: -1),
            IntSize(width: 16_385, height: 1), IntSize(width: 1, height: 16_385),
        ] {
            assertRejected(source: source, destination: Size(width: 1, height: 1))
        }
    }

    func testMaximumSourceDimensionsNeedNoSourcePixelAllocation() async throws {
        let sampling = try plan(source: IntSize(width: 16_384, height: 16_384), destination: Size(width: 1, height: 1))
        XCTAssertEqual(sampling.samplingKind, 2)
        XCTAssertNil(sampling.validationFailure(sourceSize: IntSize(width: 16_384, height: 16_384)))
    }

    func testNonlegacyPlansRejectNonpositiveAndNonfiniteDestinations() async {
        for destination in [
            Size(width: 0, height: 8), Size(width: 8, height: 0),
            Size(width: -1, height: 8), Size(width: 8, height: -1),
            Size(width: .nan, height: 8), Size(width: 8, height: .nan),
            Size(width: .infinity, height: 8), Size(width: 8, height: .infinity),
            Size(width: .greatestFiniteMagnitude, height: 8),
        ] {
            assertRejected(destination: destination)
        }
    }

    func testEveryCapRejectsNegativeFractionalAndNonfiniteValues() async {
        let fields: [WritableKeyPath<EdgeInsets, Double>] = [\.top, \.leading, \.bottom, \.trailing]
        for field in fields {
            for invalid in [Double(-1), 0.5, .nan, .infinity] {
                var caps = EdgeInsets.zero
                caps[keyPath: field] = invalid
                assertRejected(caps: caps)
            }
        }
    }

    func testCapsMustLeavePositiveSourceAndDestinationCenters() async {
        let sourceExhaustingCaps = [
            EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0),
            EdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 3),
            EdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 4),
            EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0),
            EdgeInsets(top: 5, leading: 0, bottom: 3, trailing: 0),
            EdgeInsets(top: 5, leading: 0, bottom: 4, trailing: 0),
        ]
        for mode in [ImageSamplingMode.stretch, .tile] {
            for caps in sourceExhaustingCaps { assertRejected(caps: caps, mode: mode) }
            for destination in [
                Size(width: 4, height: 16), Size(width: 3, height: 16),
                Size(width: 16, height: 4), Size(width: 16, height: 3),
            ] {
                assertRejected(
                    destination: destination,
                    caps: EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2), mode: mode)
            }
        }
    }

    func testTilePhaseAdmits4096AndRejectsTheNextFractionalLength() async throws {
        XCTAssertEqual(ImageSamplingPlan.maximumTilePhase, 4_096)
        let limit = try plan(source: IntSize(width: 1, height: 1), destination: Size(width: 4_096, height: 4_096))
        XCTAssertEqual(limit.centerRepeatX, 4_096)
        XCTAssertEqual(limit.centerRepeatY, 4_096)
        assertRejected(source: IntSize(width: 1, height: 1), destination: Size(width: 4_096.25, height: 1))
        assertRejected(source: IntSize(width: 1, height: 1), destination: Size(width: 1, height: 4_096.25))
        // Repeat count is only 256 here. The logical center length still exceeds the phase budget.
        assertRejected(source: IntSize(width: 16, height: 16), destination: Size(width: 4_096.25, height: 16))
        assertRejected(source: IntSize(width: 16, height: 16), destination: Size(width: 16, height: 4_096.25))
    }

    func testTilePhaseBudgetExcludesTheFixedCaps() async throws {
        let caps = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
        let sampling = try plan(
            source: IntSize(width: 4, height: 4), destination: Size(width: 4_098, height: 4_098), caps: caps)
        XCTAssertEqual(sampling.centerRepeatX, 2_048)
        XCTAssertEqual(sampling.centerRepeatY, 2_048)
        assertRejected(
            source: IntSize(width: 4, height: 4), destination: Size(width: 4_098.25, height: 4_098), caps: caps)
    }

    func testDescriptorValidationRejectsUnknownKindsBadFractionsAndUnboundedRepeats() async throws {
        let source = IntSize(width: 8, height: 8)
        let valid = try plan(source: source, destination: Size(width: 16, height: 16))
        var unknown = valid
        unknown.samplingKind = 42
        XCTAssertNotNil(unknown.validationFailure(sourceSize: source))
        let capFields: [WritableKeyPath<ImageSamplingDescriptor, Float>] = [
            \.sourceCapLeft, \.sourceCapTop, \.sourceCapRight, \.sourceCapBottom,
            \.destinationCapLeft, \.destinationCapTop, \.destinationCapRight, \.destinationCapBottom,
        ]
        for field in capFields {
            for value in [Float(-0.25), 1, .nan, .infinity] {
                var invalid = valid
                invalid[keyPath: field] = value
                XCTAssertNotNil(invalid.validationFailure(sourceSize: source))
            }
        }
        let repeatFields: [WritableKeyPath<ImageSamplingDescriptor, Float>] = [\.centerRepeatX, \.centerRepeatY]
        for field in repeatFields {
            for value in [Float(0), -1, 4_097, .nan, .infinity] {
                var invalid = valid
                invalid[keyPath: field] = value
                XCTAssertNotNil(invalid.validationFailure(sourceSize: source))
            }
        }
        var fractionalSourceCap = valid
        fractionalSourceCap.sourceCapLeft = 1.5 / 8
        fractionalSourceCap.destinationCapLeft = 1.5 / 16
        XCTAssertNotNil(fractionalSourceCap.validationFailure(sourceSize: source))
    }

    func testNonlegacyDescriptorRejectsPartialOrReversedUVs() async throws {
        let source = IntSize(width: 8, height: 8)
        let sampling = try plan(source: source, destination: Size(width: 16, height: 16))
        XCTAssertNil(sampling.validationFailure(sourceSize: source))
        XCTAssertNotNil(sampling.validationFailure(sourceSize: source, uvX: 0.125))
        XCTAssertNotNil(sampling.validationFailure(sourceSize: source, uvY: 0.125))
        XCTAssertNotNil(sampling.validationFailure(sourceSize: source, uvW: 0.5))
        XCTAssertNotNil(sampling.validationFailure(sourceSize: source, uvH: 0.5))
        XCTAssertNotNil(sampling.validationFailure(sourceSize: source, uvW: -1))
        XCTAssertNotNil(sampling.validationFailure(sourceSize: source, uvX: .nan))
    }

    func testMillionsOfTilesStillBridgeToOnePrimitiveAndOneOriginalPixel() async throws {
        let bitmap = solidPixel()
        let sampling = try plan(source: IntSize(width: 1, height: 1), destination: Size(width: 4_096, height: 4_096))
        let frame = RenderFrame(
            clearColor: .clear,
            commands: [
                .drawBitmap(
                    DrawBitmapCommand(
                        rect: Rect(x: 0, y: 0, width: 4_096, height: 4_096), bitmap: bitmap, sampling: sampling))
            ])
        // Inspect representation only; never allocate a destination-sized raster for this case.
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 4, height: 4))
        let images = scene.layers.flatMap { $0.images }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.sampling, sampling)
        XCTAssertEqual(images.first?.screenW, 4_096)
        XCTAssertEqual(scene.imageResources.count, 1)
        XCTAssertEqual(scene.imageResources.first?.bitmap.contentKey, bitmap.contentKey)
        XCTAssertEqual(scene.imageResources.first?.bitmap.pixels.count, 4)
    }

    func testCPUDefaultStretchRetainsTheOriginalClampLinearPixels() async throws {
        let source = BitmapSurface(width: 2, height: 1, bytesPerRow: 8, pixels: Data([0, 0, 255, 255, 0, 255, 0, 255]))
        let rect = Rect(x: 0, y: 0, width: 4, height: 1)
        let sampling = try plan(source: IntSize(width: 2, height: 1), destination: rect.size, mode: .stretch)
        let scene = makeScene(bitmap: source, sampling: sampling, rect: rect)
        let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 4, height: 1))
        let frame = RenderFrame(
            clearColor: .clear, commands: [.drawBitmap(DrawBitmapCommand(rect: rect, bitmap: source))])
        XCTAssertEqual(
            GPUIRawSceneRasterizer.rasterize(frame, size: IntSize(width: 4, height: 1)).pixels, pixels.pixels)
        let expected: [[UInt8]] = [[0, 0, 255, 255], [0, 64, 191, 255], [0, 191, 64, 255], [0, 255, 0, 255]]
        for x in 0..<4 { assertBGRA(pixels, x: x, y: 0, expected: expected[x]) }
    }

    func testCPUTilingPaintsPartialLastTilesAndKeepsPhaseWhenClipped() async throws {
        let colors: [[UInt8]] = [
            [0, 0, 255, 255], [0, 255, 0, 255], [255, 0, 0, 255],
            [255, 255, 0, 255], [255, 0, 255, 255], [0, 255, 255, 255],
        ]
        let source = BitmapSurface(width: 3, height: 2, bytesPerRow: 12, pixels: Data(colors.flatMap { $0 }))
        let sampling = try plan(source: IntSize(width: 3, height: 2), destination: Size(width: 8, height: 5))
        let rect = Rect(x: 1, y: 1, width: 8, height: 5)
        for clip in [Rect(x: 0, y: 0, width: 10, height: 7), Rect(x: 3, y: 2, width: 4, height: 3)] {
            let scene = makeScene(bitmap: source, sampling: sampling, rect: rect, clip: clip)
            let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 10, height: 7))
            let frame = RenderFrame(
                clearColor: .clear,
                commands: [
                    .drawBitmap(DrawBitmapCommand(rect: rect, bitmap: source, clipRect: clip, sampling: sampling))
                ])
            XCTAssertEqual(
                GPUIRawSceneRasterizer.rasterize(frame, size: IntSize(width: 10, height: 7)).pixels, pixels.pixels)
            for y in 0..<7 {
                for x in 0..<10 {
                    let inside =
                        x >= 1 && x < 9 && y >= 1 && y < 6
                        && Double(x) >= clip.minX && Double(x) < clip.maxX
                        && Double(y) >= clip.minY && Double(y) < clip.maxY
                    let expected = inside ? colors[((y - 1) % 2) * 3 + (x - 1) % 3] : [0, 0, 0, 0]
                    assertBGRA(pixels, x: x, y: y, expected: expected)
                }
            }
        }
    }

    func testCPUCapsKeepLogicalThicknessAtFractionalDisplayScales() async throws {
        let colors: [[UInt8]] = (0..<9).map { (index: Int) -> [UInt8] in
            let blue = UInt8(index * 20)
            let green = UInt8(240 - index * 20)
            let red = UInt8(25 + index * 20)
            return [blue, green, red, 255]
        }
        let source = BitmapSurface(width: 3, height: 3, bytesPerRow: 12, pixels: Data(colors.flatMap { $0 }))
        let caps = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
        for mode in [ImageSamplingMode.stretch, .tile] {
            let sampling = try plan(
                source: IntSize(width: 3, height: 3), destination: Size(width: 8, height: 8), caps: caps, mode: mode)
            for scale in [1.0, 1.25, 1.5, 2.0] {
                let extent = Int32(8 * scale)
                let scene = makeScene(
                    bitmap: source, sampling: sampling, rect: Rect(x: 0, y: 0, width: 8 * scale, height: 8 * scale))
                let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: extent, height: extent))
                for y in 0..<Int(extent) {
                    for x in 0..<Int(extent) {
                        let logicalX = (Double(x) + 0.5) / scale
                        let logicalY = (Double(y) + 0.5) / scale
                        let column = logicalX < 1 ? 0 : (logicalX < 7 ? 1 : 2)
                        let row = logicalY < 1 ? 0 : (logicalY < 7 ? 1 : 2)
                        assertBGRA(pixels, x: x, y: y, expected: colors[row * 3 + column])
                    }
                }
            }
        }
    }

    func testCPUWrappedTransparentEdgesFilterPremultipliedTexelsBeforeOpacity() async throws {
        let source = BitmapSurface(width: 2, height: 1, bytesPerRow: 8, pixels: Data([0, 0, 255, 255, 0, 255, 0, 0]))
        let sampling = try plan(source: IntSize(width: 2, height: 1), destination: Size(width: 4, height: 1))
        let rect = Rect(x: 0.5, y: 0, width: 4, height: 1)
        for opacity in [Float(1), 0.5] {
            let scene = makeScene(bitmap: source, sampling: sampling, rect: rect, opacity: opacity)
            let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 5, height: 1))
            let premultiplied = makeScene(
                bitmap: source.premultipliedAlpha(), sampling: sampling, rect: rect, opacity: opacity)
            let premultipliedPixels = GPUIRawSceneRasterizer.rasterize(
                premultiplied, size: IntSize(width: 5, height: 1))
            XCTAssertEqual(pixels.pixels, premultipliedPixels.pixels)
            for x in 0..<4 {
                assertBGRA(pixels, x: x, y: 0, expected: [0, 0, 255, opacity == 1 ? 128 : 64])
            }
            assertBGRA(pixels, x: 4, y: 0, expected: [0, 0, 0, 0])
        }
    }

    func testCurrentTargetImagesRequireCanonicalLegacySampling() async throws {
        let sourceSize = IntSize(width: 4, height: 4)
        let parentSize = IntSize(width: 8, height: 8)
        let pass = GPUISceneImageRenderPass(
            textureID: 7, scene: GPUIScene(clearColor: .clear), size: sourceSize, input: .currentTarget)
        let original = ImagePrimitive(screenX: 2, screenY: 2, screenW: 4, screenH: 4, textureID: 7)
        XCTAssertNil(pass.currentTargetImageDefect(original))
        XCTAssertNotNil(pass.currentTargetRegion(for: original, parentSize: parentSize))

        let caps = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
        let destination = Size(width: 8, height: 8)
        let descriptors = [
            try plan(source: sourceSize, destination: destination, caps: caps, mode: .stretch),
            try plan(source: sourceSize, destination: destination, caps: caps, mode: .tile),
            try plan(source: sourceSize, destination: destination, mode: .tile),
        ]
        let reason = "current-target images require legacy sampling without caps or tiling"
        for descriptor in descriptors {
            XCTAssertNil(descriptor.validationFailure(sourceSize: sourceSize))
            var image = original
            image.sampling = descriptor
            XCTAssertEqual(pass.currentTargetImageDefect(image), reason)
            XCTAssertNil(pass.currentTargetRegion(for: image, parentSize: parentSize))

            var scene = GPUIScene(clearColor: .clear)
            scene.bindImageRenderPass(pass)
            scene.addImage(image)
            XCTAssertEqual(scene.layers[0].images.count, 1, "Ordinary image sampling admission remains valid")
            XCTAssertEqual(
                scene.validate(), [SceneDefect(kind: .invalidImageRenderPass(textureID: 7, reason: reason))])

            var independent = pass
            independent.input = .independent
            scene.bindImageRenderPass(independent)
            XCTAssertNil(independent.currentTargetImageDefect(image))
            XCTAssertTrue(scene.validate().isEmpty, "Independent image passes retain cap/tile sampling")
        }

        var malformedLegacy = original
        malformedLegacy.sampling.samplingPadding = 1
        XCTAssertEqual(pass.currentTargetImageDefect(malformedLegacy), reason)
        XCTAssertNil(pass.currentTargetRegion(for: malformedLegacy, parentSize: parentSize))
    }

    private func plan(
        source: IntSize = IntSize(width: 8, height: 8),
        destination: Size = Size(width: 16, height: 16),
        caps: EdgeInsets = .zero,
        mode: ImageSamplingMode = .tile
    ) throws -> ImageSamplingDescriptor {
        try ImageSamplingPlan.resolve(sourceSize: source, destinationSize: destination, capInsets: caps, mode: mode)
            .get()
    }

    private func assertRejected(
        source: IntSize = IntSize(width: 8, height: 8),
        destination: Size = Size(width: 16, height: 16),
        caps: EdgeInsets = .zero,
        mode: ImageSamplingMode = .tile,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .success = ImageSamplingPlan.resolve(
            sourceSize: source, destinationSize: destination, capInsets: caps, mode: mode)
        {
            XCTFail("Unsupported sampling inputs were admitted", file: file, line: line)
        }
    }

    private func assertTap(
        _ tap: ImageSamplingAxisTap, low: Int, high: Int, fraction: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(tap.low, low, file: file, line: line)
        XCTAssertEqual(tap.high, high, file: file, line: line)
        XCTAssertEqual(tap.fraction, fraction, accuracy: 0.00001, file: file, line: line)
    }

    private func solidPixel() -> BitmapSurface {
        BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 255, 255]))
    }

    private func makeScene(
        bitmap: BitmapSurface, sampling: ImageSamplingDescriptor, rect: Rect,
        clip: Rect = Rect(x: 0, y: 0, width: 32, height: 32), opacity: Float = 1
    ) -> GPUIScene {
        var scene = GPUIScene(clearColor: .clear)
        let textureID = scene.registerImageResource(bitmap)
        scene.addImage(
            ImagePrimitive(
                screenX: Float(rect.minX), screenY: Float(rect.minY), screenW: Float(rect.size.width),
                screenH: Float(rect.size.height),
                opacity: opacity,
                clipX: Float(clip.minX), clipY: Float(clip.minY), clipWidth: Float(clip.size.width),
                clipHeight: Float(clip.size.height),
                textureID: textureID, sampling: sampling))
        scene.finish()
        return scene
    }

    private func assertBGRA(
        _ bitmap: BitmapSurface, x: Int, y: Int, expected: [UInt8],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        for channel in 0..<4 {
            XCTAssertLessThanOrEqual(
                abs(Int(bitmap.pixels[offset + channel]) - Int(expected[channel])), 1,
                "Pixel (\(x), \(y)) channel \(channel)", file: file, line: line)
        }
    }
}
