import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@MainActor
final class FrameBitmapPlacementAdmissionTests: XCTestCase {
    private let rect = Rect(x: 2, y: 2, width: 8, height: 6)
    private let size = IntSize(width: 16, height: 12)

    private func bitmap() -> BitmapSurface {
        BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 255, 0, 255]))
    }

    private func rejectedCommand() -> RenderCommand {
        var sampling = ImageSamplingDescriptor.legacy
        sampling.samplingKind = 2
        return .drawBitmap(
            DrawBitmapCommand(
                rect: rect, bitmap: BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data()),
                sampling: sampling, placement: .devicePixelRaster))
    }

    private func validFrame() -> RenderFrame {
        RenderFrame(
            clearColor: .clear,
            commands: [
                .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 16, height: 12), color: .black)),
                .drawBitmap(DrawBitmapCommand(rect: rect, bitmap: bitmap(), placement: .destinationRect)),
                .fillRect(FillRectCommand(rect: Rect(x: 4, y: 3, width: 2, height: 2), color: .white)),
            ])
    }

    private func mixedFrame() -> RenderFrame {
        var frame = validFrame()
        frame.commands.insert(rejectedCommand(), at: 1)
        frame.commands.append(rejectedCommand())
        return frame
    }

    private var expectedFailures: [FrameBitmapPlacementFailure] {
        [1, 4].map {
            FrameBitmapPlacementFailure(commandIndex: $0, reason: .devicePixelRasterRequiresCanonicalLegacySampling)
        }
    }

    func testPlacementFailureIsSeparateFromSamplingFailure() async {
        let source = bitmap()
        var command = DrawBitmapCommand(rect: rect, bitmap: source)
        XCTAssertEqual(command.placement, .destinationRect)
        XCTAssertNil(command.placementFailure)
        command.placement = .devicePixelRaster
        XCTAssertNil(command.placementFailure)
        for kind: Int32 in [1, 2, 99] {
            command.sampling = .legacy
            command.sampling.samplingKind = kind
            XCTAssertEqual(command.placementFailure, .devicePixelRasterRequiresCanonicalLegacySampling)
        }
        command.sampling = .legacy
        command.sampling.sourceCapLeft = 0.5
        XCTAssertTrue(command.sampling.isLegacy)
        XCTAssertEqual(command.placementFailure, .devicePixelRasterRequiresCanonicalLegacySampling)
        command.placement = .destinationRect
        XCTAssertNil(command.placementFailure, "Sampler validation remains a separate admission rule")
        XCTAssertNotNil(command.sampling.validationFailure())
    }

    func testValidFrameRetainsItsCommandsAndHasNoPlacementFailures() async {
        let frame = validFrame()
        let admission = frame.admittingBitmapPlacements()
        XCTAssertEqual(admission.frame, frame)
        XCTAssertTrue(admission.failures.isEmpty)
        var observed: [FrameBitmapPlacementFailure] = []
        admission.reportFailures(to: { observed.append($0) })
        XCTAssertTrue(observed.isEmpty)
    }

    func testNonfiniteAndUnrepresentableDestinationsRejectBeforeBridgeResourceRegistration() async {
        let overflow = Double(Float.greatestFiniteMagnitude) * 2
        let cases: [(Rect, BitmapPlacementFailure)] = [
            (Rect(x: .nan, y: 0, width: 8, height: 6), .nonfiniteDestinationGeometry),
            (Rect(x: 0, y: .infinity, width: 8, height: 6), .nonfiniteDestinationGeometry),
            (Rect(x: 0, y: 0, width: .infinity, height: 6), .nonfiniteDestinationGeometry),
            (Rect(x: 0, y: 0, width: 8, height: -.infinity), .nonfiniteDestinationGeometry),
            (
                Rect(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 6),
                .nonfiniteDestinationGeometry
            ),
            (Rect(x: overflow, y: 0, width: 8, height: 6), .unrepresentableDestinationGeometry),
            (Rect(x: 0, y: 0, width: overflow, height: 6), .unrepresentableDestinationGeometry),
            (Rect(x: 0, y: 0, width: 8, height: Double.leastNonzeroMagnitude), .unrepresentableDestinationGeometry),
            (Rect(x: overflow / 3, y: 0, width: overflow / 3, height: 6), .unrepresentableDestinationGeometry),
        ]
        for (destination, reason) in cases {
            let invalid = DrawBitmapCommand(
                rect: destination, bitmap: BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data()))
            XCTAssertEqual(invalid.sampling, .legacy)
            XCTAssertEqual(invalid.placementFailure, reason)
            var frame = validFrame()
            frame.commands.insert(.drawBitmap(invalid), at: 1)
            var observed: [FrameBitmapPlacementFailure] = []
            let scene = GPUIScene(
                from: frame, surfaceSize: Size(width: 16, height: 12),
                onBitmapPlacementFailure: { observed.append($0) })
            XCTAssertEqual(observed, [FrameBitmapPlacementFailure(commandIndex: 1, reason: reason)])
            XCTAssertEqual(scene, GPUIScene(from: validFrame(), surfaceSize: Size(width: 16, height: 12)))
            XCTAssertEqual(scene.imageResources.count, 1)
            XCTAssertEqual(frame.commands.count, 4)
        }
    }

    func testFiniteLegacyDestinationsDoNotAcquireCapTileBudgetsOrIntegerRounding() async {
        let rectangles = [
            Rect(x: 0.25, y: 0.125, width: 0.5, height: 0.25),
            Rect(x: -1_000_000, y: -1_000_000, width: 2_000_000, height: 2_000_000),
            Rect(x: 0, y: 0, width: 4097, height: 4097),
            Rect(x: 0, y: 0, width: Double(Float.leastNonzeroMagnitude), height: 1),
            Rect(x: 0, y: 0, width: 0, height: 1),
            Rect(x: 0, y: 0, width: -1, height: 1),
        ]
        for destination in rectangles {
            let command = DrawBitmapCommand(rect: destination, bitmap: bitmap())
            XCTAssertNil(command.placementFailure)
            let frame = RenderFrame(commands: [.drawBitmap(command)])
            let admission = frame.admittingBitmapPlacements()
            XCTAssertEqual(admission.frame, frame)
            XCTAssertTrue(admission.failures.isEmpty)
            XCTAssertEqual(command.sampling, .legacy)
            XCTAssertEqual(command.rect, destination)
        }
    }

    func testAdmissionPreservesOriginalIndicesOrderAndInputFrame() async {
        let frame = mixedFrame()
        let original = frame
        let admission = frame.admittingBitmapPlacements()
        XCTAssertEqual(admission.failures, expectedFailures)
        XCTAssertEqual(admission.frame, validFrame())
        XCTAssertEqual(frame, original)
        XCTAssertEqual(frame.commands.count, 5)
        XCTAssertEqual(admission.frame.commands.count, 3)
    }

    func testEmptyLogicalDestinationsRemainAdmittedWithoutPaintingInEitherMode() async {
        let control = validFrame()
        let controlScene = GPUIScene(from: control, surfaceSize: Size(width: 16, height: 12))
        let expected = GPUIRawSceneRasterizer.rasterize(control, size: size)
        let destinations = [
            Rect(x: 12.25, y: 8.5, width: 0, height: 3),
            Rect(x: 12.25, y: 8.5, width: 3, height: 0),
            Rect(x: 12.25, y: 8.5, width: -1, height: 3),
            Rect(x: 12.25, y: 8.5, width: 3, height: -1),
            Rect(x: 12.25, y: 8.5, width: 0, height: 0),
            Rect(x: 12.25, y: 8.5, width: -1, height: -1),
        ]
        for placement in [BitmapPlacement.destinationRect, .devicePixelRaster] {
            for destination in destinations {
                var command = DrawBitmapCommand(rect: destination, bitmap: bitmap())
                command.placement = placement
                var original = control
                original.commands.insert(.drawBitmap(command), at: 2)
                let admission = original.admittingBitmapPlacements()
                XCTAssertEqual(admission.frame, original)
                XCTAssertTrue(admission.failures.isEmpty)
                XCTAssertTrue(command.rect.isEmpty)
                var observed: [FrameBitmapPlacementFailure] = []
                let scene = GPUIScene(
                    from: original, surfaceSize: Size(width: 16, height: 12),
                    onBitmapPlacementFailure: { observed.append($0) })
                XCTAssertTrue(observed.isEmpty)
                // An admitted empty draw may register its source, but contributes no paint.
                XCTAssertEqual(scene.layers[0].images, controlScene.layers[0].images)
                let actual = GPUIRawSceneRasterizer.rasterize(
                    original, size: size, onBitmapPlacementFailure: { observed.append($0) })
                XCTAssertTrue(observed.isEmpty)
                XCTAssertEqual(actual.pixels, expected.pixels)
                XCTAssertEqual(original.commands.count, 4)
                XCTAssertEqual(original.commands[2], .drawBitmap(command))
            }
        }
    }

    func testReportContainsOnlyTypedReasonAndOriginalIndex() async {
        let admission = mixedFrame().admittingBitmapPlacements()
        var observed: [FrameBitmapPlacementFailure] = []
        admission.reportFailures(to: { observed.append($0) })
        XCTAssertEqual(observed, expectedFailures)
        XCTAssertEqual(
            observed.map(\.description),
            [
                "RenderFrame command 1 rejected: devicePixelRaster placement requires canonical legacy sampling.",
                "RenderFrame command 4 rejected: devicePixelRaster placement requires canonical legacy sampling.",
            ])
    }

    func testAdmissionPreservesClipStackCommandsAndOriginalFailureIndices() async {
        let push = RenderCommand.pushClip(ClipCommand(shape: .rect(rect, cornerRadius: 0)))
        let draw = RenderCommand.drawBitmap(DrawBitmapCommand(rect: rect, bitmap: bitmap()))
        let original = RenderFrame(commands: [push, rejectedCommand(), draw, .popClip, rejectedCommand()])
        let admission = original.admittingBitmapPlacements()
        XCTAssertEqual(admission.failures, expectedFailures)
        XCTAssertEqual(admission.frame.commands, [push, draw, .popClip])
        XCTAssertEqual(original.commands.count, 5)
    }

    func testCPUBridgeReportsOnceBeforeRegisteringAnyRejectedSource() async {
        let frame = mixedFrame()
        var observed: [FrameBitmapPlacementFailure] = []
        let scene = GPUIScene(
            from: frame, surfaceSize: Size(width: 16, height: 12),
            onBitmapPlacementFailure: { observed.append($0) })
        let expected = GPUIScene(from: validFrame(), surfaceSize: Size(width: 16, height: 12))
        XCTAssertEqual(observed, expectedFailures)
        XCTAssertEqual(scene, expected)
        XCTAssertEqual(scene.imageResources.count, 1)
        XCTAssertEqual(scene.imageResources.first?.bitmap.pixels, bitmap().pixels)
        XCTAssertEqual(scene.layers[0].images.count, 1)
        XCTAssertTrue(scene.validate().isEmpty, "The accepted partial scene remains renderable")
        XCTAssertEqual(frame.commands.count, 5)
    }

    func testRawFrameRasterizerReportsOnceAndKeepsValidSiblingPixels() async {
        var observed: [FrameBitmapPlacementFailure] = []
        let actual = GPUIRawSceneRasterizer.rasterize(
            mixedFrame(), size: size, onBitmapPlacementFailure: { observed.append($0) })
        let expected = GPUIRawSceneRasterizer.rasterize(validFrame(), size: size)
        XCTAssertEqual(observed, expectedFailures)
        XCTAssertEqual(actual.pixels, expected.pixels)
        XCTAssertEqual(actual.width, size.width)
        XCTAssertEqual(actual.height, size.height)
    }

    func testCPUFrameBackendUsesTheAdmittingBridgeForInvalidSources() async throws {
        let renderer = CPUBatchRenderer()
        try renderer.attach(to: SurfaceDescriptor(offscreenPixelSize: size))
        defer { renderer.detach() }
        try renderer.render(frame: mixedFrame())
        let actual = try XCTUnwrap(renderer.lastRenderedBitmap)
        let expected = GPUIRawSceneRasterizer.rasterize(validFrame(), size: size)
        XCTAssertEqual(actual.pixels, expected.pixels)
    }

    func testDeviceRasterCPUPreviewRetainsOriginalLogicalCommandGeometry() async {
        let source = BitmapSurface(width: 29, height: 15, bytesPerRow: 116, pixels: Data(repeating: 255, count: 1740))
        let destination = Rect(x: 10.25, y: 5.5, width: 18.8, height: 9.6)
        let frame = RenderFrame(commands: [
            .drawBitmap(DrawBitmapCommand(rect: destination, bitmap: source, placement: .devicePixelRaster))
        ])
        var observed: [FrameBitmapPlacementFailure] = []
        let scene = GPUIScene(
            from: frame, surfaceSize: Size(width: 64, height: 32),
            onBitmapPlacementFailure: { observed.append($0) })
        XCTAssertTrue(observed.isEmpty)
        XCTAssertEqual(scene.layers[0].images.first?.screenX, Float(destination.origin.x))
        XCTAssertEqual(scene.layers[0].images.first?.screenY, Float(destination.origin.y))
        XCTAssertEqual(scene.layers[0].images.first?.screenW, Float(destination.size.width))
        XCTAssertEqual(scene.layers[0].images.first?.screenH, Float(destination.size.height))
        XCTAssertEqual(scene.imageResources.first?.bitmap.contentKey, source.contentKey)
    }

    func testOriginalNonthrowingFrameFunctionTypesRemainAvailable() async {
        let commandInitializer:
            (Rect, BitmapSurface, Float, Rect?, BlendMode, ImageSamplingDescriptor) -> DrawBitmapCommand =
                DrawBitmapCommand.init(rect:bitmap:opacity:clipRect:blendMode:sampling:)
        XCTAssertEqual(commandInitializer(rect, bitmap(), 1, nil, .normal, .legacy).placement, .destinationRect)
        let bridge: (RenderFrame, Size) -> GPUIScene = GPUIScene.init(from:surfaceSize:)
        let rasterizer: (RenderFrame, IntSize) -> BitmapSurface = GPUIRawSceneRasterizer.rasterize
        XCTAssertEqual(bridge(validFrame(), Size(width: 16, height: 12)).imageResources.count, 1)
        XCTAssertEqual(rasterizer(validFrame(), size).width, size.width)
    }
}
