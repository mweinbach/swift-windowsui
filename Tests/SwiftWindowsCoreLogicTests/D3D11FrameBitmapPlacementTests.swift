import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Analytic coverage of the preparation and geometry used by the native frame
/// branches. These tests do not create an HWND, issue a draw, or prove pixels.
@MainActor
final class D3D11FrameBitmapPlacementTests: XCTestCase {
    private func bitmap(width: Int32 = 1, height: Int32 = 1) -> BitmapSurface {
        BitmapSurface(
            width: width, height: height, bytesPerRow: width * 4,
            pixels: Data(repeating: 255, count: Int(width * height * 4)))
    }

    func testDefaultLegacyBitmapKeepsRequestedDestinationAtEveryScale() async {
        let source = bitmap()
        let rectangles = [
            Rect(x: 4, y: 2, width: 8, height: 6),
            Rect(x: 10.25, y: 5.5, width: 18.75, height: 9.5),
            Rect(x: 0, y: 16, width: 96, height: 64),
            Rect(x: 3, y: 3, width: 2, height: 2),
        ]
        for source in [source, bitmap(width: 24, height: 16)] {
            for destination in rectangles {
                let command = DrawBitmapCommand(rect: destination, bitmap: source)
                XCTAssertEqual(command.placement, .destinationRect)
                XCTAssertEqual(command.sampling, .legacy)
                for scale in [1.0, 1.25, 1.5, 2.0] {
                    let scaledCommand = scaled(bitmap: command, factor: scale)
                    XCTAssertEqual(scaledCommand.rect, destination.scaled(by: scale))
                    XCTAssertEqual(logicalBitmapRect(for: command, scaleFactor: scale), destination)
                    XCTAssertEqual(scaledCommand.bitmap.pixels, source.pixels)
                    XCTAssertEqual(scaledCommand.bitmap.contentKey, source.contentKey)
                    XCTAssertEqual(scaledCommand.sampling, .legacy)
                    XCTAssertEqual(scaledCommand.placement, .destinationRect)
                }
            }
        }
    }

    func testDestinationClipDoesNotReplaceTheDrawExtentOrSnapItsOrigin() async {
        let command = DrawBitmapCommand(
            rect: Rect(x: 4, y: 2, width: 8, height: 6), bitmap: bitmap(),
            clipRect: Rect(x: 8, y: 3, width: 2, height: 3))
        for scale in [1.0, 1.25, 1.5, 2.0] {
            let result = scaled(bitmap: command, factor: scale)
            XCTAssertEqual(result.rect, command.rect.scaled(by: scale))
            XCTAssertEqual(result.clipRect, command.clipRect?.scaled(by: scale))
            XCTAssertNotNil(result.rect.intersected(with: result.clipRect!))
            XCTAssertEqual(logicalBitmapRect(for: command, scaleFactor: scale), command.rect)
        }
        XCTAssertEqual(
            scaled(bitmap: command, factor: 1.25).rect,
            Rect(x: 5, y: 2.5, width: 10, height: 7.5))
    }

    func testExplicitDeviceRasterKeepsTheExactFractionalScaleOracle() async {
        let command = DrawBitmapCommand(
            rect: Rect(x: 10.25, y: 5.5, width: 18.8, height: 9.6),
            bitmap: bitmap(width: 29, height: 15), placement: .devicePixelRaster)
        XCTAssertNil(command.placementFailure)
        XCTAssertEqual(scaled(bitmap: command, factor: 1.5).rect, Rect(x: 15, y: 8, width: 29, height: 15))
        XCTAssertEqual(
            logicalBitmapRect(for: command, scaleFactor: 1.5),
            Rect(x: 10, y: 16.0 / 3.0, width: 58.0 / 3.0, height: 10))
        for scale in [1.0, 1.25, 1.5, 2.0] {
            let result = scaled(bitmap: command, factor: scale)
            XCTAssertEqual(result.rect.size, Size(width: 29, height: 15))
            XCTAssertEqual(result.rect.origin.x, (command.rect.origin.x * scale).rounded(.toNearestOrAwayFromZero))
            XCTAssertEqual(result.rect.origin.y, (command.rect.origin.y * scale).rounded(.toNearestOrAwayFromZero))
        }
    }

    func testEmptyLogicalDestinationsStayEmptyInBothNativePlans() async {
        let source = bitmap(width: 29, height: 15)
        let clip = Rect(x: 0, y: 0, width: 32, height: 24)
        let destinations = [
            Rect(x: 2.25, y: 2.5, width: 0, height: 6),
            Rect(x: 2.25, y: 2.5, width: 8, height: 0),
            Rect(x: 2.25, y: 2.5, width: -1, height: 6),
            Rect(x: 2.25, y: 2.5, width: 8, height: -1),
            Rect(x: 2.25, y: 2.5, width: 0, height: 0),
            Rect(x: 2.25, y: 2.5, width: -1, height: -1),
        ]
        for placement in [BitmapPlacement.destinationRect, .devicePixelRaster] {
            for destination in destinations {
                var command = DrawBitmapCommand(rect: destination, bitmap: source, clipRect: clip)
                command.placement = placement
                let original = RenderFrame(commands: [.drawBitmap(command)])
                let admission = original.admittingBitmapPlacements()
                XCTAssertEqual(admission.frame, original)
                XCTAssertTrue(admission.failures.isEmpty)
                for scale in [1.0, 1.25, 1.5, 2.0] {
                    var observed: [FrameBitmapPlacementFailure] = []
                    let prepared = prepareFrameForNativeDrawing(
                        original, scaleFactor: scale, onFailure: { observed.append($0) })
                    XCTAssertEqual(prepared, original)
                    XCTAssertTrue(observed.isEmpty)
                    XCTAssertTrue(frameSupportsDirect2DImageSampling(prepared))
                    let pixelCommand = scaled(bitmap: command, factor: scale)
                    let logicalRect = logicalBitmapRect(for: command, scaleFactor: scale)
                    XCTAssertEqual(pixelCommand.rect, destination.scaled(by: scale))
                    XCTAssertTrue(pixelCommand.rect.isEmpty)
                    XCTAssertEqual(logicalRect, destination)
                    XCTAssertTrue(logicalRect.isEmpty)
                    XCTAssertEqual(pixelCommand.clipRect, clip.scaled(by: scale))
                    XCTAssertEqual(pixelCommand.bitmap, source)
                    XCTAssertEqual(pixelCommand.placement, placement)
                }
            }
        }
    }

    func testFramePlacementCopyPreservesEveryOtherCommandField() async {
        let source = bitmap(width: 3, height: 3)
        for placement in [BitmapPlacement.destinationRect, .devicePixelRaster] {
            let command = DrawBitmapCommand(
                rect: Rect(x: 1.25, y: 2.5, width: 7, height: 5), bitmap: source, opacity: 0.625,
                clipRect: Rect(x: 2, y: 3, width: 4, height: 2), blendMode: .multiply,
                sampling: .legacy, placement: placement)
            let result = scaled(bitmap: command, factor: 1.5)
            XCTAssertEqual(result.bitmap, command.bitmap)
            XCTAssertEqual(result.bitmap.contentKey, command.bitmap.contentKey)
            XCTAssertEqual(result.opacity, command.opacity)
            XCTAssertEqual(result.blendMode, command.blendMode)
            XCTAssertEqual(result.sampling, command.sampling)
            XCTAssertEqual(result.placement, command.placement)
            XCTAssertEqual(result.clipRect, command.clipRect?.scaled(by: 1.5))
        }
    }

    func testCapAndTileDestinationSamplingDoesNotAcquirePhysicalPlacement() async throws {
        let source = bitmap(width: 3, height: 3)
        let destination = Rect(x: 1.25, y: 2.5, width: 7, height: 5)
        for mode in [ImageSamplingMode.stretch, .tile] {
            let descriptor = try ImageSamplingPlan.resolve(
                sourceSize: IntSize(width: source.width, height: source.height), destinationSize: destination.size,
                capInsets: EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1), mode: mode
            ).get()
            let command = DrawBitmapCommand(
                rect: destination, bitmap: source, opacity: 0.5,
                clipRect: Rect(x: 2, y: 3, width: 4, height: 2), blendMode: .screen,
                sampling: descriptor, placement: .destinationRect)
            for scale in [1.0, 1.25, 1.5, 2.0] {
                let result = scaled(bitmap: command, factor: scale)
                XCTAssertEqual(result.rect, destination.scaled(by: scale))
                XCTAssertEqual(result.clipRect, command.clipRect?.scaled(by: scale))
                XCTAssertEqual(result.sampling, descriptor)
                XCTAssertEqual(result.bitmap.contentKey, source.contentKey)
                XCTAssertEqual(result.opacity, command.opacity)
                XCTAssertEqual(result.blendMode, command.blendMode)
                XCTAssertEqual(result.placement, .destinationRect)
                XCTAssertNil(frameBitmapSamplingFailure(result))
            }
        }
    }

    func testNativePreparationRejectsBeforeEitherBackendCapabilityChoice() async throws {
        let source = bitmap(width: 3, height: 3)
        let destination = Rect(x: 0, y: 0, width: 7, height: 5)
        let descriptor = try ImageSamplingPlan.resolve(
            sourceSize: IntSize(width: source.width, height: source.height), destinationSize: destination.size,
            capInsets: .zero, mode: .tile
        ).get()
        let rejected = DrawBitmapCommand(
            rect: destination,
            bitmap: BitmapSurface(width: 3, height: 3, bytesPerRow: 12, pixels: Data()),
            sampling: descriptor, placement: .devicePixelRaster)
        let leading = RenderCommand.fillRect(FillRectCommand(rect: destination, color: .white))
        let trailing = RenderCommand.fillRect(FillRectCommand(rect: destination, color: .black))
        let droppedPath = RenderCommand.fillPath(FillPathCommand(path: RenderPath(), color: .clear))
        for expectedDirect2D in [true, false] {
            let accepted = DrawBitmapCommand(
                rect: destination, bitmap: source, sampling: expectedDirect2D ? .legacy : descriptor,
                placement: .destinationRect)
            let original = RenderFrame(
                clearColor: .white,
                commands: [leading, droppedPath, .drawBitmap(rejected), .drawBitmap(accepted), trailing])
            var failures: [FrameBitmapPlacementFailure] = []
            let prepared = prepareFrameForNativeDrawing(original, scaleFactor: 1, onFailure: { failures.append($0) })
            XCTAssertEqual(
                failures,
                [
                    FrameBitmapPlacementFailure(
                        commandIndex: 2, reason: .devicePixelRasterRequiresCanonicalLegacySampling)
                ])
            XCTAssertEqual(prepared.clearColor, original.clearColor)
            XCTAssertEqual(prepared.commands, [leading, .drawBitmap(accepted), trailing])
            XCTAssertEqual(frameSupportsDirect2DImageSampling(prepared), expectedDirect2D)
            XCTAssertEqual(
                original.commands, [leading, droppedPath, .drawBitmap(rejected), .drawBitmap(accepted), trailing])
        }
    }

    func testCanonicalDeviceRasterDoesNotChangeDirect2DCapabilitySelection() async {
        let command = DrawBitmapCommand(
            rect: Rect(x: 0, y: 0, width: 18.8, height: 9.6), bitmap: bitmap(width: 29, height: 15),
            placement: .devicePixelRaster)
        let frame = RenderFrame(commands: [.drawBitmap(command)])
        var failures: [FrameBitmapPlacementFailure] = []
        let prepared = prepareFrameForNativeDrawing(frame, scaleFactor: 1.5, onFailure: { failures.append($0) })
        XCTAssertEqual(prepared, frame)
        XCTAssertTrue(failures.isEmpty)
        XCTAssertTrue(frameSupportsDirect2DImageSampling(prepared))
        XCTAssertEqual(command.sampling, .legacy)
    }

    func testNativeScaleOverflowRejectsBeforeDrawingAndRetainsOriginalIndex() async {
        let halfFloatLimit = Double(Float.greatestFiniteMagnitude) / 2
        let cases: [(Rect, Double, BitmapPlacementFailure)] = [
            (Rect(x: 1, y: 2, width: 8, height: 6), .infinity, .nonfiniteDestinationGeometry),
            (Rect(x: 1, y: 2, width: 8, height: 6), .nan, .nonfiniteDestinationGeometry),
            (Rect(x: 0, y: 0, width: halfFloatLimit, height: 6), 3, .unrepresentableDestinationGeometry),
            (Rect(x: 1, y: 0, width: 8, height: 6), .greatestFiniteMagnitude, .nonfiniteDestinationGeometry),
        ]
        let leading = RenderCommand.fillRect(
            FillRectCommand(rect: Rect(x: 0, y: 0, width: 2, height: 2), color: .white))
        for (destination, scale, reason) in cases {
            let command = DrawBitmapCommand(
                rect: destination, bitmap: BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data()))
            XCTAssertNil(command.placementFailure, "The logical rectangle itself is representable")
            XCTAssertEqual(nativeFrameBitmapPlacementFailure(command, scaleFactor: scale), reason)
            let original = RenderFrame(commands: [leading, .drawBitmap(command)])
            var observed: [FrameBitmapPlacementFailure] = []
            let prepared = prepareFrameForNativeDrawing(
                original, scaleFactor: scale, onFailure: { observed.append($0) })
            XCTAssertEqual(observed, [FrameBitmapPlacementFailure(commandIndex: 1, reason: reason)])
            XCTAssertEqual(prepared.commands, [leading])
            XCTAssertEqual(original.commands.count, 2)
        }
        let representable = DrawBitmapCommand(
            rect: Rect(x: 0, y: 0, width: halfFloatLimit, height: 6), bitmap: bitmap())
        XCTAssertNil(nativeFrameBitmapPlacementFailure(representable, scaleFactor: 1.5))
    }
}
