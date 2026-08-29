import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Analytic Windows layout and source-preservation oracles, not captured
/// native SwiftUI pixels. Preserving the old fallback when fit declines a
/// proposal does not qualify native fixedSize or unbounded behavior.
@MainActor
final class WinSwiftUIBitmapAspectFitTests: XCTestCase {
    private static let size = IntSize(width: 24, height: 24)
    private static let caps = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)

    private func bitmap(width: Int32, height: Int32) -> BitmapSurface {
        BitmapSurface(
            width: width, height: height, bytesPerRow: width * 4,
            pixels: Data((0..<(Int(width) * Int(height))).flatMap { _ in [UInt8(0), 255, 0, 255] }))
    }

    private func snapshot<Content: View>(_ content: Content, displayScale: Double = 1) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: content.frame(width: 24, height: 24, alignment: .topLeading),
            size: Self.size, displayScale: displayScale, clearColor: .clear)
    }

    private func snapshot(runtime: RetainedViewRuntime) -> WinSwiftUIRenderSnapshot {
        let scene = runtime.renderScene()
        return WinSwiftUIRenderSnapshot(
            runtime: runtime, frame: runtime.renderFrame(), scene: scene, size: Self.size, displayScale: 1)
    }

    private func bitmapCommands(in frame: RenderFrame) -> [DrawBitmapCommand] {
        frame.commands.compactMap {
            guard case .drawBitmap(let command) = $0 else { return nil }
            return command
        }
    }

    private func imageNode(in runtime: RetainedViewRuntime) throws -> ViewNode {
        var pending = [runtime.root]
        var images: [ViewNode] = []
        while let node = pending.popLast() {
            if node.bitmapSurface != nil { images.append(node) }
            pending.append(contentsOf: node.children)
        }
        XCTAssertEqual(images.count, 1)
        return try XCTUnwrap(images.first)
    }

    @discardableResult
    private func assertImage(
        _ result: WinSwiftUIRenderSnapshot, source: BitmapSurface, rect: Rect,
        sampling: ImageSamplingDescriptor = .legacy,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ImagePrimitive {
        let node = try imageNode(in: result.runtime)
        XCTAssertEqual(node.resolvedFrame.size, rect.size, file: file, line: line)
        XCTAssertEqual(node.bitmapSurface?.width, source.width, file: file, line: line)
        XCTAssertEqual(node.bitmapSurface?.height, source.height, file: file, line: line)
        XCTAssertEqual(node.bitmapSurface?.pixels, source.pixels, file: file, line: line)
        XCTAssertEqual(node.bitmapSurface?.contentKey, source.contentKey, file: file, line: line)
        XCTAssertNil(node.imageSamplingFailure, file: file, line: line)

        let images = result.scene.layers.flatMap(\.images)
        XCTAssertEqual(images.count, 1, file: file, line: line)
        XCTAssertEqual(result.scene.imageResources.count, 1, file: file, line: line)
        XCTAssertEqual(result.scene.imageResources.first?.bitmap, source, file: file, line: line)
        XCTAssertEqual(result.scene.imageResources.first?.bitmap.contentKey, source.contentKey, file: file, line: line)
        XCTAssertTrue(result.scene.imageRenderPasses.isEmpty, file: file, line: line)
        XCTAssertTrue(result.scene.validate().isEmpty, file: file, line: line)
        let image = try XCTUnwrap(images.first, file: file, line: line)
        let scale = result.displayScale
        XCTAssertEqual(image.screenX, Float(rect.origin.x * scale), file: file, line: line)
        XCTAssertEqual(image.screenY, Float(rect.origin.y * scale), file: file, line: line)
        XCTAssertEqual(image.screenW, Float(rect.width * scale), file: file, line: line)
        XCTAssertEqual(image.screenH, Float(rect.height * scale), file: file, line: line)
        XCTAssertEqual(image.sampling, sampling, file: file, line: line)
        XCTAssertEqual(image.uvX, 0, file: file, line: line)
        XCTAssertEqual(image.uvY, 0, file: file, line: line)
        XCTAssertEqual(image.uvW, 1, file: file, line: line)
        XCTAssertEqual(image.uvH, 1, file: file, line: line)
        let imageRuns = result.scene.presentationOrder().filter { $0.kind == .image }
        XCTAssertEqual(imageRuns.count, 1, file: file, line: line)
        XCTAssertEqual(imageRuns.first?.range, 0..<1, file: file, line: line)

        let commands = bitmapCommands(in: result.frame)
        XCTAssertEqual(commands.count, 1, file: file, line: line)
        let command = try XCTUnwrap(commands.first, file: file, line: line)
        // Frame records use logical coordinates; scene primitives use pixels.
        XCTAssertEqual(command.rect, rect, file: file, line: line)
        XCTAssertEqual(command.bitmap, source, file: file, line: line)
        XCTAssertEqual(command.bitmap.contentKey, source.contentKey, file: file, line: line)
        XCTAssertEqual(command.sampling, sampling, file: file, line: line)
        return image
    }

    /// A solid integer-edged rectangle is an independent coverage oracle. It
    /// neither reads the measured result nor uses the image sampling planner.
    private func expectedPixels(size: IntSize, visibleRect: Rect) -> Data {
        var bytes: [UInt8] = []
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                let inside =
                    Double(x) + 0.5 >= visibleRect.minX && Double(x) + 0.5 < visibleRect.maxX
                    && Double(y) + 0.5 >= visibleRect.minY && Double(y) + 0.5 < visibleRect.maxY
                bytes.append(contentsOf: inside ? [0, 255, 0, 255] : [0, 0, 0, 0])
            }
        }
        return Data(bytes)
    }

    private func assertCoverage(
        _ result: WinSwiftUIRenderSnapshot, visibleRect: Rect, opaquePixels: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let scale = result.displayScale
        let pixelSize = IntSize(
            width: Int32(Double(result.size.width) * scale), height: Int32(Double(result.size.height) * scale))
        let deviceRect = Rect(
            x: visibleRect.minX * scale, y: visibleRect.minY * scale,
            width: visibleRect.width * scale, height: visibleRect.height * scale)
        let scenePixels = GPUIRawSceneRasterizer.rasterize(result.scene, size: pixelSize)
        XCTAssertEqual(
            scenePixels.pixels, expectedPixels(size: pixelSize, visibleRect: deviceRect), file: file, line: line)
        let count = stride(from: 3, to: scenePixels.pixels.count, by: 4).filter { scenePixels.pixels[$0] == 255 }.count
        XCTAssertEqual(count, opaquePixels, file: file, line: line)
        let framePixels = GPUIRawSceneRasterizer.rasterize(result.frame, size: result.size)
        XCTAssertEqual(
            framePixels.pixels, expectedPixels(size: result.size, visibleRect: visibleRect), file: file, line: line)
    }

    private func cappedSampling(tiled: Bool) -> ImageSamplingDescriptor {
        ImageSamplingDescriptor(
            sourceCapLeft: 1 / 6, sourceCapTop: 1 / 4, sourceCapRight: 1 / 6, sourceCapBottom: 1 / 4,
            destinationCapLeft: 1 / 24, destinationCapTop: 1 / 16,
            destinationCapRight: 1 / 24, destinationCapBottom: 1 / 16,
            centerRepeatX: tiled ? 5.5 : 1, centerRepeatY: tiled ? 7 : 1,
            samplingKind: tiled ? 2 : 1)
    }

    func testWideBitmapFitsTheLiveProposalWithEmptyBands() async throws {
        let source = bitmap(width: 4, height: 2)
        let result = snapshot(Image(bitmap: source).resizable().scaledToFit().frame(width: 12, height: 12))
        let rect = Rect(x: 0, y: 3, width: 12, height: 6)
        try assertImage(result, source: source, rect: rect)
        assertCoverage(result, visibleRect: rect, opaquePixels: 72)
        let leaf = try imageNode(in: result.runtime)
        let fit = try XCTUnwrap(leaf.parent)
        XCTAssertEqual(fit.aspectFitLayout, RetainedAspectFitLayout())
        XCTAssertTrue(fit.layoutFillAxes.isEmpty)
        XCTAssertTrue(fit.effectiveFillAxes.isEmpty)
        XCTAssertEqual(fit.preferredSize, Size(width: 4, height: 2), "The ideal must not pin the finite fit result")

        // The nil ratio is resolved from the current child, not a build-time
        // ratio or a previous placed rectangle with the same modifier node.
        let portrait = bitmap(width: 2, height: 4)
        leaf.bitmapSurface = portrait
        let changed = snapshot(runtime: result.runtime)
        let changedRect = Rect(x: 3, y: 0, width: 6, height: 12)
        try assertImage(changed, source: portrait, rect: changedRect)
        assertCoverage(changed, visibleRect: changedRect, opaquePixels: 72)
        XCTAssertTrue(try imageNode(in: changed.runtime) === leaf)
    }

    func testTallBitmapFitsWithoutFillingTheOtherAxis() async throws {
        let source = bitmap(width: 2, height: 4)
        let result = snapshot(Image(bitmap: source).resizable().scaledToFit().frame(width: 12, height: 8))
        let rect = Rect(x: 4, y: 0, width: 4, height: 8)
        try assertImage(result, source: source, rect: rect)
        assertCoverage(result, visibleRect: rect, opaquePixels: 32)
    }

    func testExplicitRatioChangesDestinationButKeepsSourceBytes() async throws {
        let source = bitmap(width: 4, height: 2)
        let result = snapshot(
            Image(bitmap: source).resizable().aspectRatio(1, contentMode: .fit).frame(width: 12, height: 8))
        let rect = Rect(x: 2, y: 0, width: 8, height: 8)
        try assertImage(result, source: source, rect: rect)
        assertCoverage(result, visibleRect: rect, opaquePixels: 64)
    }

    func testSmallerProposalShrinksBothDimensionsTogether() async throws {
        let source = bitmap(width: 12, height: 8)
        let result = snapshot(Image(bitmap: source).resizable().scaledToFit().frame(width: 6, height: 6))
        let rect = Rect(x: 0, y: 1, width: 6, height: 4)
        try assertImage(result, source: source, rect: rect)
        assertCoverage(result, visibleRect: rect, opaquePixels: 24)
    }

    func testEnclosingFrameOwnsFitAlignment() async throws {
        let source = bitmap(width: 4, height: 2)
        for (alignment, y) in [(Alignment.topLeading, 0.0), (.bottomTrailing, 6.0)] {
            let result = snapshot(
                Image(bitmap: source).resizable().scaledToFit().frame(width: 12, height: 12, alignment: alignment))
            let rect = Rect(x: 0, y: y, width: 12, height: 6)
            try assertImage(result, source: source, rect: rect)
            assertCoverage(result, visibleRect: rect, opaquePixels: 72)
        }
    }

    func testGenericFitUsesTheSameProposalPathAsTypedImageFit() async throws {
        let source = bitmap(width: 4, height: 2)
        let image = Image(bitmap: source).resizable()
        let rect = Rect(x: 0, y: 3, width: 12, height: 6)
        let direct = snapshot(image.scaledToFit().frame(width: 12, height: 12))
        let directPrimitive = try assertImage(direct, source: source, rect: rect)
        for wrapped in [AnyView(AnyView(image).scaledToFit()), AnyView(image.opacity(1).scaledToFit())] {
            let result = snapshot(wrapped.frame(width: 12, height: 12))
            let primitive = try assertImage(result, source: source, rect: rect)
            assertCoverage(result, visibleRect: rect, opaquePixels: 72)
            XCTAssertEqual(primitive.sampling, directPrimitive.sampling)
            XCTAssertEqual(
                try imageNode(in: result.runtime).parent?.aspectFitLayout,
                try imageNode(in: direct.runtime).parent?.aspectFitLayout)
        }
    }

    func testLargerOuterFrameAlignsTheEarlierFitFrame() async throws {
        let source = bitmap(width: 4, height: 2)
        let result = snapshot(
            Image(bitmap: source).resizable().scaledToFit().frame(width: 12, height: 12)
                .frame(width: 20, height: 20, alignment: .bottomTrailing))
        let rect = Rect(x: 8, y: 11, width: 12, height: 6)
        try assertImage(result, source: source, rect: rect)
        assertCoverage(result, visibleRect: rect, opaquePixels: 72)
    }

    func testFrameBeforeGenericFitKeepsItsAcceptedDimensions() async throws {
        let source = bitmap(width: 4, height: 2)
        let result = snapshot(
            Image(bitmap: source).resizable().frame(width: 12, height: 8).scaledToFit()
                .frame(width: 20, height: 20))
        let rect = Rect(x: 4, y: 6, width: 12, height: 8)
        try assertImage(result, source: source, rect: rect)
        assertCoverage(result, visibleRect: rect, opaquePixels: 96)
        let frame = try XCTUnwrap(try imageNode(in: result.runtime).parent)
        let fit = try XCTUnwrap(frame.parent)
        XCTAssertEqual(frame.preferredSize, Size(width: 12, height: 8))
        XCTAssertEqual(frame.fixedPreferredSizeAxes, .both)
        XCTAssertEqual(fit.aspectFitLayout, RetainedAspectFitLayout())
        XCTAssertEqual(fit.resolvedFrame.size, Size(width: 12, height: 8))
    }

    func testRatioAndProposalReconciliationKeepTheBitmapLeaf() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.size)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 24, height: 24) }, invalidateHandler: {})
        let source = bitmap(width: 4, height: 2)
        var ratio = 2.0
        var frameSize = Size(width: 12, height: 8)
        host.setComponents {
            [
                Image(bitmap: source).resizable().aspectRatio(ratio, contentMode: .fit)
                    .frame(width: frameSize.width, height: frameSize.height).makeComponent(context: context)
            ]
        }
        let initial = snapshot(runtime: runtime)
        let retained = try imageNode(in: runtime)
        let fit = try XCTUnwrap(retained.parent)
        let initialRect = Rect(x: 0, y: 1, width: 12, height: 6)
        try assertImage(initial, source: source, rect: initialRect)
        assertCoverage(initial, visibleRect: initialRect, opaquePixels: 72)

        ratio = 1
        host.reload()
        let square = snapshot(runtime: runtime)
        let squareRect = Rect(x: 2, y: 0, width: 8, height: 8)
        try assertImage(square, source: source, rect: squareRect)
        assertCoverage(square, visibleRect: squareRect, opaquePixels: 64)
        XCTAssertTrue(try imageNode(in: runtime) === retained)
        XCTAssertTrue(retained.parent === fit)
        XCTAssertEqual(fit.aspectFitLayout, RetainedAspectFitLayout(aspectRatio: 1))

        frameSize = Size(width: 8, height: 12)
        host.reload()
        let resized = snapshot(runtime: runtime)
        let resizedRect = Rect(x: 0, y: 2, width: 8, height: 8)
        try assertImage(resized, source: source, rect: resizedRect)
        assertCoverage(resized, visibleRect: resizedRect, opaquePixels: 64)
        XCTAssertTrue(try imageNode(in: runtime) === retained)
        XCTAssertTrue(retained.parent === fit)
    }

    func testFitResolvesCapFractionsFromTheFittedDestination() async throws {
        let source = bitmap(width: 6, height: 4)
        let result = snapshot(
            Image(bitmap: source).resizable(capInsets: Self.caps).scaledToFit().frame(width: 24, height: 24))
        let rect = Rect(x: 0, y: 4, width: 24, height: 16)
        try assertImage(result, source: source, rect: rect, sampling: cappedSampling(tiled: false))
        assertCoverage(result, visibleRect: rect, opaquePixels: 384)
        XCTAssertEqual(try imageNode(in: result.runtime).imageCapInsets, Self.caps)
    }

    func testCappedTileFitKeepsOnePrimitiveAndTheOriginalSource() async throws {
        let source = bitmap(width: 6, height: 4)
        let result = snapshot(
            Image(bitmap: source).resizable(capInsets: Self.caps, resizingMode: .tile).scaledToFit()
                .frame(width: 24, height: 24))
        let rect = Rect(x: 0, y: 4, width: 24, height: 16)
        try assertImage(result, source: source, rect: rect, sampling: cappedSampling(tiled: true))
        assertCoverage(result, visibleRect: rect, opaquePixels: 384)
        XCTAssertEqual(source.pixels.count, 96)
        XCTAssertEqual(try imageNode(in: result.runtime).imageResizingMode, .tile)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.stride, 128)
    }

    func testDisplayScaleKeepsLogicalFitCapsAndTilePhase() async throws {
        let source = bitmap(width: 6, height: 4)
        let rect = Rect(x: 0, y: 4, width: 24, height: 16)
        for (scale, count) in [(1.0, 384), (1.25, 600), (1.5, 864), (2.0, 1536)] {
            for mode in [Image.ResizingMode.stretch, .tile] {
                let result = snapshot(
                    Image(bitmap: source).resizable(capInsets: Self.caps, resizingMode: mode).scaledToFit()
                        .frame(width: 24, height: 24), displayScale: scale)
                try assertImage(result, source: source, rect: rect, sampling: cappedSampling(tiled: mode == .tile))
                assertCoverage(result, visibleRect: rect, opaquePixels: count)
            }
        }
    }

    func testClippingChangesCoverageWithoutChangingTheFitRectangle() async throws {
        let source = bitmap(width: 4, height: 2)
        let content = Image(bitmap: source).resizable().scaledToFit().frame(width: 12, height: 12)
            .offset(x: 4, y: 2).frame(width: 12, height: 12, alignment: .topLeading)
        let unclipped = snapshot(content)
        let clipped = snapshot(content.clipped())
        let rect = Rect(x: 4, y: 5, width: 12, height: 6)
        try assertImage(unclipped, source: source, rect: rect)
        try assertImage(clipped, source: source, rect: rect)
        assertCoverage(unclipped, visibleRect: rect, opaquePixels: 72)
        assertCoverage(clipped, visibleRect: Rect(x: 4, y: 5, width: 8, height: 6), opaquePixels: 48)
    }

    func testOrdinaryStretchDoesNotAcquireAspectFitOrNewSampling() async throws {
        let source = bitmap(width: 2, height: 1)
        let result = snapshot(Image(bitmap: source).resizable().frame(width: 6, height: 10))
        let rect = Rect(x: 0, y: 0, width: 6, height: 10)
        try assertImage(result, source: source, rect: rect)
        assertCoverage(result, visibleRect: rect, opaquePixels: 60)
        let leaf = try imageNode(in: result.runtime)
        XCTAssertNil(leaf.aspectFitLayout)
        XCTAssertNil(leaf.parent?.aspectFitLayout)
        XCTAssertEqual(leaf.layoutFillAxes, .both)
        XCTAssertNil(leaf.preferredSize)
    }

    func testNonResizableBitmapKeepsItsIntrinsicCenteredRectangle() async throws {
        let source = bitmap(width: 2, height: 2)
        let result = snapshot(Image(bitmap: source).frame(width: 8, height: 8))
        let rect = Rect(x: 3, y: 3, width: 2, height: 2)
        try assertImage(result, source: source, rect: rect)
        assertCoverage(result, visibleRect: rect, opaquePixels: 4)
        let leaf = try imageNode(in: result.runtime)
        XCTAssertFalse(leaf.imageUsesBitmapResizing)
        XCTAssertTrue(leaf.layoutFillAxes.isEmpty)
        XCTAssertEqual(leaf.preferredSize, Size(width: 2, height: 2))
    }

    func testFittedTilePhaseLimitRemainsATypedSamplingFailure() async throws {
        let source = bitmap(width: 1, height: 1)
        let limit = Int32(ImageSamplingPlan.maximumTilePhase)
        XCTAssertEqual(limit, 4096)
        // These snapshots only emit records. Do not call assertCoverage or any
        // rasterizer: no output bitmap is allocated at this destination size.
        let accepted = WinSwiftUIRendererSnapshotter.snapshot(
            of: Image(bitmap: source).resizable(resizingMode: .tile).scaledToFit(),
            size: IntSize(width: limit, height: limit), clearColor: .clear)
        try assertImage(
            accepted, source: source, rect: Rect(x: 0, y: 0, width: Double(limit), height: Double(limit)),
            sampling: ImageSamplingDescriptor(
                centerRepeatX: Float(limit), centerRepeatY: Float(limit), samplingKind: 2))
        XCTAssertEqual(accepted.scene.imageResources.first?.bitmap.pixels.count, 4)

        let rejected = WinSwiftUIRendererSnapshotter.snapshot(
            of: Image(bitmap: source).resizable(resizingMode: .tile).scaledToFit(),
            size: IntSize(width: limit + 1, height: limit + 1), clearColor: .clear)
        let leaf = try imageNode(in: rejected.runtime)
        XCTAssertEqual(leaf.resolvedFrame.size, Size(width: Double(limit + 1), height: Double(limit + 1)))
        XCTAssertEqual(leaf.bitmapSurface, source)
        XCTAssertEqual(leaf.bitmapSurface?.contentKey, source.contentKey)
        XCTAssertEqual(leaf.imageSamplingFailure, .phaseLimitExceeded)
        XCTAssertTrue(rejected.scene.layers.flatMap(\.images).isEmpty)
        XCTAssertTrue(rejected.scene.presentationOrder().filter { $0.kind == .image }.isEmpty)
        XCTAssertTrue(rejected.scene.imageRenderPasses.isEmpty)
        XCTAssertTrue(bitmapCommands(in: rejected.frame).isEmpty)
    }

    func testFixedSizeFitKeepsTheLegacyCenteredStackClamp() async throws {
        let source = bitmap(width: 4, height: 2)
        let result = snapshot(
            Image(bitmap: source).resizable().frame(width: 12, height: 8)
                .aspectRatio(1, contentMode: .fit).fixedSize().frame(width: 20, height: 20))
        let rect = Rect(x: 6, y: 6, width: 8, height: 8)
        try assertImage(result, source: source, rect: rect)
        assertCoverage(result, visibleRect: rect, opaquePixels: 64)
        let innerFrame = try XCTUnwrap(try imageNode(in: result.runtime).parent)
        let fit = try XCTUnwrap(innerFrame.parent)
        XCTAssertEqual(innerFrame.preferredSize, Size(width: 12, height: 8))
        XCTAssertEqual(innerFrame.fixedPreferredSizeAxes, .both)
        XCTAssertEqual(innerFrame.resolvedFrame.size, Size(width: 8, height: 8))
        XCTAssertEqual(fit.preferredSize, Size(width: 8, height: 8))
        XCTAssertEqual(fit.resolvedFrame.size, Size(width: 8, height: 8))
        let constraints = try XCTUnwrap(fit.cachedMeasureKey).constraints
        XCTAssertTrue(constraints.maxWidth.isInfinite)
        XCTAssertTrue(constraints.maxHeight.isInfinite)
    }

    func testUnboundedVStackFitKeepsTheLegacyCenteredStackClamp() async throws {
        let source = bitmap(width: 4, height: 2)
        let content = VStack(spacing: 0) {
            Image(bitmap: source).resizable().frame(width: 12, height: 8)
                .aspectRatio(1, contentMode: .fit)
        }
        let result = snapshot(content.frame(width: 20, height: 20))
        let rect = Rect(x: 6, y: 6, width: 8, height: 8)
        try assertImage(result, source: source, rect: rect)
        assertCoverage(result, visibleRect: rect, opaquePixels: 64)
        let innerFrame = try XCTUnwrap(try imageNode(in: result.runtime).parent)
        let fit = try XCTUnwrap(innerFrame.parent)
        XCTAssertEqual(innerFrame.resolvedFrame.size, Size(width: 8, height: 8))
        XCTAssertEqual(fit.preferredSize, Size(width: 8, height: 8))
        XCTAssertEqual(fit.resolvedFrame.size, Size(width: 8, height: 8))
        XCTAssertTrue(try XCTUnwrap(fit.cachedMeasureKey).constraints.maxHeight.isInfinite)
    }

    func testReconciliationAlternatesFiniteFitAndLegacyFallbackWithoutReplacingTheLeaf() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.size)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 24, height: 24) }, invalidateHandler: {})
        let source = bitmap(width: 4, height: 2)
        var usesFixedSize = false
        host.setComponents {
            [
                Image(bitmap: source).resizable().frame(width: 12, height: 8)
                    .aspectRatio(1, contentMode: .fit)
                    .fixedSize(horizontal: usesFixedSize, vertical: usesFixedSize)
                    .frame(width: 20, height: 20).makeComponent(context: context)
            ]
        }
        let retained = try imageNode(in: runtime)
        let fit = try XCTUnwrap(retained.parent?.parent)
        let cases = [
            (false, Rect(x: 4, y: 6, width: 12, height: 8), 96),
            (true, Rect(x: 6, y: 6, width: 8, height: 8), 64),
            (false, Rect(x: 4, y: 6, width: 12, height: 8), 96),
        ]
        for (fixedSize, rect, count) in cases {
            usesFixedSize = fixedSize
            host.reload()
            let result = snapshot(runtime: runtime)
            try assertImage(result, source: source, rect: rect)
            assertCoverage(result, visibleRect: rect, opaquePixels: count)
            XCTAssertTrue(try imageNode(in: runtime) === retained)
            XCTAssertTrue(retained.parent?.parent === fit)
            XCTAssertEqual(fit.preferredSize, Size(width: 8, height: 8))
            XCTAssertTrue(fit.effectiveFillAxes.isEmpty)
            let constraints = try XCTUnwrap(fit.cachedMeasureKey).constraints
            XCTAssertEqual(constraints.maxWidth, fixedSize ? .infinity : 20)
            XCTAssertEqual(constraints.maxHeight, fixedSize ? .infinity : 20)
        }
    }
}
