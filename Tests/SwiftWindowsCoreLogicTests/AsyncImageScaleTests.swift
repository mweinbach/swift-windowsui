import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Analytic source-density and retained-coordinate oracles. These are not
/// captured native SwiftUI pixels or new gallery baselines.
@MainActor
final class AsyncImageScaleTests: XCTestCase {
    func testTwoPixelsPerPointChangesIntrinsicSizeWithoutChangingSourceBytes() async throws {
        let source = bitmap(width: 12, height: 8)
        let result = snapshot(Image(bitmap: source, scale: 2))
        let leaf = try imageNode(result.runtime)
        XCTAssertEqual(leaf.intrinsicContentSize(), Size(width: 6, height: 4))
        XCTAssertEqual(leaf.imageBitmapScale, 2)
        try assertImage(result, source: source, logicalSize: Size(width: 6, height: 4))
    }

    func testFractionalDensityChangesIntrinsicSizeInLogicalPoints() async throws {
        let source = bitmap(width: 9, height: 6)
        let result = snapshot(Image(bitmap: source, scale: 1.5))
        XCTAssertEqual(try imageNode(result.runtime).intrinsicContentSize(), Size(width: 6, height: 4))
        try assertImage(result, source: source, logicalSize: Size(width: 6, height: 4))
    }

    func testUnconstrainedResizableImageUsesTheDensityAdjustedFallback() async throws {
        let source = bitmap(width: 12, height: 8)
        for density in [1.0, 1.5, 2.0] {
            let result = snapshot(Image(bitmap: source, scale: density).resizable().fixedSize())
            let expected = Size(width: 12 / density, height: 8 / density)
            let leaf = try imageNode(result.runtime)
            XCTAssertNil(leaf.preferredSize, "The fallback must not pin a finite resizable proposal")
            XCTAssertEqual(leaf.intrinsicContentSize(), expected)
            try assertImage(result, source: source, logicalSize: expected)
        }
    }

    func testFiniteStretchStillAcceptsTheProposalAtNondefaultDensity() async throws {
        let source = bitmap(width: 12, height: 8)
        let result = snapshot(Image(bitmap: source, scale: 2).resizable().frame(width: 24, height: 12))
        try assertImage(result, source: source, logicalSize: Size(width: 24, height: 12))
    }

    func testFiniteAspectFitKeepsRatioAndPointPlacementAtNondefaultDensity() async throws {
        let source = bitmap(width: 12, height: 8)
        let result = snapshot(Image(bitmap: source, scale: 2).resizable().scaledToFit().frame(width: 24, height: 24))
        try assertImage(result, source: source, logicalSize: Size(width: 24, height: 16))
        let command = try bitmapCommand(result)
        XCTAssertEqual(command.rect.origin, Point(x: 0, y: 4))
    }

    func testCappedStretchConvertsPointCapsToSourceTexelsExactlyOnce() async throws {
        let source = bitmap(width: 12, height: 8)
        let caps = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
        let result = snapshot(
            Image(bitmap: source, scale: 2).resizable(capInsets: caps).frame(width: 24, height: 16))
        let expected = ImageSamplingDescriptor(
            sourceCapLeft: 1 / 6, sourceCapTop: 1 / 4, sourceCapRight: 1 / 6, sourceCapBottom: 1 / 4,
            destinationCapLeft: 1 / 24, destinationCapTop: 1 / 16,
            destinationCapRight: 1 / 24, destinationCapBottom: 1 / 16,
            samplingKind: 1)
        try assertImage(result, source: source, logicalSize: Size(width: 24, height: 16), sampling: expected)
        XCTAssertEqual(try imageNode(result.runtime).imageCapInsets, caps, "Authored metadata remains in points")
    }

    func testCappedTileUsesLogicalCenterPeriodsAtTwoPixelsPerPoint() async throws {
        let source = bitmap(width: 12, height: 8)
        let caps = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
        let result = snapshot(
            Image(bitmap: source, scale: 2).resizable(capInsets: caps, resizingMode: .tile)
                .frame(width: 24, height: 16))
        // Source center: (12-4)/2 by (8-4)/2 = 4 by 2 points.
        // Destination center: 22 by 14 points, so repeats are 5.5 by 7.
        let expected = ImageSamplingDescriptor(
            sourceCapLeft: 1 / 6, sourceCapTop: 1 / 4, sourceCapRight: 1 / 6, sourceCapBottom: 1 / 4,
            destinationCapLeft: 1 / 24, destinationCapTop: 1 / 16,
            destinationCapRight: 1 / 24, destinationCapBottom: 1 / 16,
            centerRepeatX: 5.5, centerRepeatY: 7, samplingKind: 2)
        try assertImage(result, source: source, logicalSize: Size(width: 24, height: 16), sampling: expected)
    }

    func testFractionalPointCapsAreAdmittedWhenDensityMapsThemToWholeTexels() async throws {
        let source = bitmap(width: 9, height: 6)
        let cap = 2.0 / 3.0
        let result = snapshot(
            Image(bitmap: source, scale: 1.5)
                .resizable(
                    capInsets: EdgeInsets(top: cap, leading: cap, bottom: cap, trailing: cap), resizingMode: .tile
                )
                .frame(width: 18, height: 12))
        let expected = ImageSamplingDescriptor(
            sourceCapLeft: 1 / 9, sourceCapTop: 1 / 6, sourceCapRight: 1 / 9, sourceCapBottom: 1 / 6,
            destinationCapLeft: 1 / 27, destinationCapTop: 1 / 18,
            destinationCapRight: 1 / 27, destinationCapBottom: 1 / 18,
            centerRepeatX: 25 / 7, centerRepeatY: 4, samplingKind: 2)
        try assertImage(result, source: source, logicalSize: Size(width: 18, height: 12), sampling: expected)
    }

    func testDensityDoesNotRoundCapsThatStillBisectSourceTexels() async throws {
        let source = bitmap(width: 9, height: 6)
        let result = snapshot(
            Image(bitmap: source, scale: 1.5)
                .resizable(capInsets: EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1))
                .frame(width: 18, height: 12))
        XCTAssertEqual(try imageNode(result.runtime).imageSamplingFailure, .fractionalCapInsets)
        XCTAssertTrue(result.scene.layers.flatMap(\.images).isEmpty)
        XCTAssertTrue(
            result.frame.commands.compactMap { command -> DrawBitmapCommand? in
                if case .drawBitmap(let bitmap) = command { return bitmap }
                return nil
            }.isEmpty)
    }

    func testDisplayScaleChangesOnlyPlacementNotDensityOrTileCount() async throws {
        let source = bitmap(width: 6, height: 3)
        let expected = ImageSamplingDescriptor(centerRepeatX: 3, centerRepeatY: 4, samplingKind: 2)
        for displayScale in [1.0, 1.25, 2.0] {
            let result = snapshot(
                Image(bitmap: source, scale: 1.5).resizable(resizingMode: .tile).frame(width: 12, height: 8),
                displayScale: displayScale)
            try assertImage(result, source: source, logicalSize: Size(width: 12, height: 8), sampling: expected)
            let command = try bitmapCommand(result)
            XCTAssertEqual(command.rect, Rect(x: 0, y: 0, width: 12, height: 8))
            let image = try XCTUnwrap(result.scene.layers.flatMap(\.images).first)
            XCTAssertEqual(image.screenW, Float(12 * displayScale))
            XCTAssertEqual(image.screenH, Float(8 * displayScale))
        }
    }

    func testInvalidScaleFallsBackToOneWithoutResamplingOrChangingTheURLIdentity() async throws {
        let source = bitmap(width: 6, height: 4)
        for invalid in [0, -2, Double.nan, Double.infinity, -Double.infinity] {
            let result = snapshot(Image(bitmap: source, scale: invalid))
            XCTAssertEqual(try imageNode(result.runtime).imageBitmapScale, 1)
            try assertImage(result, source: source, logicalSize: Size(width: 6, height: 4))
            let identity = AsyncImageSource(url: URL(string: "https://async-image.invalid/density"), service: nil)
            let presentation = AsyncImagePresentation(source: identity, scale: invalid)
            XCTAssertEqual(presentation.source, identity)
            XCTAssertEqual(presentation.scale, 1)
        }
    }

    func testExtremeFiniteDensityDoesNotDropValidUncappedStretchPlacements() async throws {
        let source = bitmap(width: 2, height: 2)
        for density in [Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude] {
            for extent in [2.0, 0.5] {
                let result = snapshot(
                    Image(bitmap: source, scale: density).resizable().frame(width: extent, height: extent))
                try assertImage(result, source: source, logicalSize: Size(width: extent, height: extent))
                XCTAssertEqual(try imageNode(result.runtime).imageBitmapScale, density)
            }
        }
    }

    func testLargePointPlacementIsNotRejectedUsingItsLargerTexelExtent() async throws {
        let source = bitmap(width: 3, height: 3)
        let node = Controls.image(source, frame: Rect(x: 0, y: 0, width: 600_000, height: 600_000))
        node.imageBitmapScale = 2
        node.imageUsesBitmapResizing = true
        node.imageResizingMode = .stretch
        node.imageCapInsets = EdgeInsets(top: 0.5, leading: 0.5, bottom: 0.5, trailing: 0.5)
        let sampling = try XCTUnwrap(node.resolvedBitmapImageSampling(source))
        XCTAssertNil(node.imageSamplingFailure)
        XCTAssertEqual(sampling.sourceCapLeft, 1 / 3)
        XCTAssertEqual(sampling.destinationCapLeft, 1 / 1_200_000)
        XCTAssertNil(sampling.placementValidationFailure(rect: node.frame))
        XCTAssertEqual(source.pixels.count, 36, "No destination-sized bitmap is allocated by this oracle")
    }

    func testSmallDensityCannotAdmitAnOversizedActualPointPlacement() async throws {
        let result = ImageSamplingPlan.resolve(
            sourceSize: IntSize(width: 4, height: 4),
            destinationSize: Size(width: 1_000_001, height: 4),
            capInsets: EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2),
            mode: .stretch, sourceScale: 0.5)
        // Choose whole source caps on both axes; placement is the rejecting
        // boundary, not a source-size, cap-alignment or destination-center error.
        let aligned = ImageSamplingPlan.resolve(
            sourceSize: IntSize(width: 4, height: 4),
            destinationSize: Size(width: 1_000_001, height: 8),
            capInsets: EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2),
            mode: .stretch, sourceScale: 0.5)
        XCTAssertEqual(result, .failure(.fractionalCapInsets))
        XCTAssertEqual(aligned, .failure(.unrepresentableDescriptor))
    }

    func testExtremeAndInvalidNonlegacyDensityKeepsExplicitSamplingFailures() async throws {
        for invalid in [0, -1, Double.nan, Double.infinity] {
            XCTAssertEqual(
                ImageSamplingPlan.resolve(
                    sourceSize: IntSize(width: 3, height: 3), destinationSize: Size(width: 2, height: 2),
                    capInsets: .zero, mode: .tile, sourceScale: invalid),
                .failure(.invalidSourceScale))
        }
        XCTAssertEqual(
            ImageSamplingPlan.resolve(
                sourceSize: IntSize(width: 3, height: 3), destinationSize: Size(width: 2, height: 2),
                capInsets: .zero, mode: .tile, sourceScale: .greatestFiniteMagnitude),
            .failure(.phaseLimitExceeded))
        XCTAssertEqual(
            ImageSamplingPlan.resolve(
                sourceSize: IntSize(width: 3, height: 3), destinationSize: Size(width: 0.5, height: 0.5),
                capInsets: .zero, mode: .tile, sourceScale: .leastNonzeroMagnitude),
            .failure(.unrepresentableDescriptor))
    }

    func testDefaultDensityPreservesTheExistingCappedTileDescriptor() async throws {
        let source = bitmap(width: 6, height: 4)
        let node = Controls.image(source, frame: Rect(x: 0, y: 0, width: 24, height: 16))
        node.imageUsesBitmapResizing = true
        node.imageResizingMode = .tile
        node.imageCapInsets = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
        XCTAssertEqual(node.imageBitmapScale, 1)
        let expected = ImageSamplingDescriptor(
            sourceCapLeft: 1 / 6, sourceCapTop: 1 / 4, sourceCapRight: 1 / 6, sourceCapBottom: 1 / 4,
            destinationCapLeft: 1 / 24, destinationCapTop: 1 / 16,
            destinationCapRight: 1 / 24, destinationCapBottom: 1 / 16,
            centerRepeatX: 5.5, centerRepeatY: 7, samplingKind: 2)
        XCTAssertEqual(node.resolvedBitmapImageSampling(source), expected)
        XCTAssertNil(node.imageSamplingFailure)
    }

    func testReconciliationChangesDensityOnTheSameBitmapLeafAndInvalidatesLayout() async throws {
        let source = bitmap(width: 12, height: 8)
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(IntSize(width: 24, height: 24))
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 24, height: 24) }, invalidateHandler: {})
        var density = 1.0
        host.setComponents {
            [Image(bitmap: source, scale: density).resizable().fixedSize().makeComponent(context: context)]
        }
        _ = runtime.renderScene()
        let retained = try imageNode(runtime)
        for next in [2.0, 1.5, 1.0] {
            density = next
            host.reload()
            _ = runtime.renderScene()
            let leaf = try imageNode(runtime)
            XCTAssertTrue(leaf === retained)
            XCTAssertEqual(leaf.imageBitmapScale, next)
            XCTAssertEqual(leaf.intrinsicContentSize(), Size(width: 12 / next, height: 8 / next))
            XCTAssertEqual(leaf.bitmapSurface?.contentKey, source.contentKey)
        }
        retained.imageBitmapScale = 2
        XCTAssertTrue(runtime.dirtyFlags.contains(.layout))
        XCTAssertTrue(runtime.dirtyFlags.contains(.paint))
        _ = runtime.renderScene()
        XCTAssertEqual(retained.intrinsicContentSize(), Size(width: 6, height: 4))
    }

    private func bitmap(width: Int32, height: Int32) -> BitmapSurface {
        BitmapSurface(
            width: width, height: height, bytesPerRow: width * 4,
            pixels: Data((0..<(Int(width) * Int(height))).flatMap { _ in [UInt8(0), 255, 0, 255] }))
    }

    private func snapshot<Content: View>(_ content: Content, displayScale: Double = 1) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: content.frame(width: 24, height: 24, alignment: .topLeading),
            size: IntSize(width: 24, height: 24), displayScale: displayScale, clearColor: .clear)
    }

    private func imageNode(_ runtime: RetainedViewRuntime) throws -> ViewNode {
        var pending = [runtime.root]
        var images: [ViewNode] = []
        while let node = pending.popLast() {
            if node.bitmapSurface != nil { images.append(node) }
            pending.append(contentsOf: node.children)
        }
        XCTAssertEqual(images.count, 1)
        return try XCTUnwrap(images.first)
    }

    private func bitmapCommand(_ result: WinSwiftUIRenderSnapshot) throws -> DrawBitmapCommand {
        let commands = result.frame.commands.compactMap { command -> DrawBitmapCommand? in
            if case .drawBitmap(let bitmap) = command { return bitmap }
            return nil
        }
        XCTAssertEqual(commands.count, 1)
        return try XCTUnwrap(commands.first)
    }

    private func assertImage(
        _ result: WinSwiftUIRenderSnapshot, source: BitmapSurface, logicalSize: Size,
        sampling: ImageSamplingDescriptor = .legacy,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let leaf = try imageNode(result.runtime)
        XCTAssertEqual(leaf.resolvedFrame.size, logicalSize, file: file, line: line)
        XCTAssertEqual(leaf.bitmapSurface?.contentKey, source.contentKey, file: file, line: line)
        XCTAssertEqual(leaf.bitmapSurface?.pixels, source.pixels, file: file, line: line)
        XCTAssertNil(leaf.imageSamplingFailure, file: file, line: line)
        let images = result.scene.layers.flatMap(\.images)
        XCTAssertEqual(images.count, 1, file: file, line: line)
        XCTAssertTrue(result.scene.validate().isEmpty, file: file, line: line)
        let image = try XCTUnwrap(images.first, file: file, line: line)
        XCTAssertEqual(image.sampling, sampling, file: file, line: line)
        XCTAssertEqual(result.scene.imageResources.first?.bitmap.contentKey, source.contentKey, file: file, line: line)
        let command = try bitmapCommand(result)
        XCTAssertEqual(command.rect.size, logicalSize, file: file, line: line)
        XCTAssertEqual(command.sampling, sampling, file: file, line: line)
        XCTAssertEqual(command.bitmap.contentKey, source.contentKey, file: file, line: line)
        XCTAssertEqual(image.screenW, Float(logicalSize.width * result.displayScale), file: file, line: line)
        XCTAssertEqual(image.screenH, Float(logicalSize.height * result.displayScale), file: file, line: line)
    }
}
