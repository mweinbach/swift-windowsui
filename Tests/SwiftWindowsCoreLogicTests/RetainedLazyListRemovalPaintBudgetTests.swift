import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedLazyListRemovalPaintBudgetTests: XCTestCase {
    private enum FixtureFailure: Error { case capture }

    private func source(
        color: Float = 1, extent: Int32 = 2, dependent: Bool = false
    ) throws -> RetainedLazyListPaintSource {
        var scene = GPUIScene(clearColor: .clear)
        var quad = QuadPrimitive(
            width: Float(extent), height: Float(extent), startR: color, endR: color)
        quad.blurRadius = dependent ? 1 : 0
        scene.addQuad(quad)
        guard
            case .captured(let result) = RetainedLazyListPaintSource.capture(
                scene: scene, ranges: [0..<scene.paintRecordCount],
                surfaceSize: IntSize(width: extent, height: extent))
        else {
            XCTFail("Expected a captured source made entirely from native values")
            throw FixtureFailure.capture
        }
        return result
    }

    private func paint(
        color: Float = 1, extent: Int32 = 2, dependent: Bool = false
    ) throws -> RetainedLazyListRemovalPaint {
        let source = try source(color: color, extent: extent, dependent: dependent)
        // A constant translation keeps the dependent-source budget fixture
        // independent of the separate inherited-opacity projection contract.
        let property: AnimatableProperty = dependent ? .transformTranslationX : .opacity
        let state = AnimationState(
            startValue: dependent ? 0 : 1, endValue: 0, startTime: 10, duration: 1, easing: .linear)
        return try XCTUnwrap(
            RetainedLazyListRemovalPaint(
                source: source,
                pose: RetainedLazyListPaintPose(
                    opacity: 1, transform: .identity, pivot: .zero, clip: nil,
                    displayScale: 1, rootOpacityIsInPrimitives: true),
                animation: RetainedRemovalTransitionAnimation(
                    initialOpacity: 1, initialTransform: .identity, frame: source.bounds,
                    states: [property: state], removalProperties: [property], resolvedAt: 10)))
    }

    func testLivePixelsAreReservedBeforeNewestDeparturesInOriginalDrawOrder() async throws {
        var live = GPUIScene(clearColor: .clear)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(QuadPrimitive(width: 32, height: 32))
        let id = live.registerImageRenderPass(child, size: IntSize(width: 32, height: 32))
        live.addImage(ImagePrimitive(screenW: 32, screenH: 32, textureID: id))
        let size = IntSize(width: 2_048, height: 2_048)
        let liveCost = try XCTUnwrap(RetainedLazyListPaintSource.executionCost(scene: live, surfaceSize: size))
        let paints = try (1...5).map { try paint(color: Float($0) / 10, extent: 2_048) }

        let selected = RetainedLazyListRemovalPaint.fittingSceneBudget(
            paints, liveCost: liveCost, surfaceSize: size, displayScale: 1)

        // Four full-size tails already exhaust the production pixel bound;
        // the live child reserves its pixels first, leaving room for three.
        XCTAssertEqual(selected.count, 3)
        XCTAssertEqual(selected.map { $0.source.scene.layers[0].quads[0].startR }, [0.3, 0.4, 0.5])
        for paint in selected { paint.append(to: &live, targetSize: size, displayScale: 1) }
        live.finish()
        XCTAssertEqual(live.imageRenderPasses.count, 4)
        XCTAssertTrue(live.validate().isEmpty)
        let resultCost = try XCTUnwrap(RetainedLazyListPaintSource.executionCost(scene: live, surfaceSize: size))
        XCTAssertLessThanOrEqual(resultCost.pixelCount, Int64(GPUISceneLimits.maxImageRenderPassTotalPixels))
    }

    func testUnpresentedLivePassDeclarationsStillReserveCapacity() async throws {
        var live = GPUIScene(clearColor: .clear)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(QuadPrimitive(width: 2, height: 2))
        for _ in 0..<(GPUISceneLimits.maxImageRenderPassCount - 1) {
            _ = live.registerImageRenderPass(child, size: IntSize(width: 2, height: 2))
        }
        let size = IntSize(width: 8, height: 8)
        XCTAssertTrue(live.validate().isEmpty)
        let liveCost = try XCTUnwrap(RetainedLazyListPaintSource.executionCost(scene: live, surfaceSize: size))
        XCTAssertEqual(liveCost.passCount, GPUISceneLimits.maxImageRenderPassCount - 1)
        let selected = RetainedLazyListRemovalPaint.fittingSceneBudget(
            [try paint(color: 0.25), try paint(color: 0.5), try paint(color: 0.75)],
            liveCost: liveCost, surfaceSize: size, displayScale: 1)

        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.source.scene.layers[0].quads[0].startR, 0.75)
        for paint in selected { paint.append(to: &live, targetSize: size, displayScale: 1) }
        live.finish()
        XCTAssertEqual(live.imageRenderPasses.count, GPUISceneLimits.maxImageRenderPassCount)
        XCTAssertTrue(live.validate().isEmpty)
    }

    func testCompletedAndIncompatibleDPIValuesAreFinishedRatherThanPostponed() async throws {
        let current = try paint(color: 0.25)
        var complete = try paint(color: 0.5)
        complete.advance(to: 11)
        let dependent = try paint(color: 0.75, extent: 8, dependent: true)
        XCTAssertEqual(dependent.source.input, .isolatedBackdrop)
        let cost = RetainedLazyListPaintSource.ExecutionCost(passCount: 0, pixelCount: 0)

        let selected = RetainedLazyListRemovalPaint.fittingSceneBudget(
            [current, complete, dependent], liveCost: cost,
            surfaceSize: IntSize(width: 8, height: 8), displayScale: 2)

        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.source.scene.layers[0].quads[0].startR, 0.25)
        let returnedToOriginalScale = RetainedLazyListRemovalPaint.fittingSceneBudget(
            selected, liveCost: cost, surfaceSize: IntSize(width: 8, height: 8), displayScale: 1)
        XCTAssertEqual(returnedToOriginalScale.count, 1)
        XCTAssertEqual(returnedToOriginalScale.first?.source.input, .independent)
    }

    func testInvalidLiveCostDoesNotAuthorizeAnyAdditionalPass() async throws {
        let values = [try paint()]
        let costs: [RetainedLazyListPaintSource.ExecutionCost?] = [
            nil,
            .init(passCount: -1, pixelCount: 0),
            .init(passCount: 0, pixelCount: -1),
            .init(passCount: GPUISceneLimits.maxImageRenderPassCount + 1, pixelCount: 0),
            .init(passCount: 0, pixelCount: Int64(GPUISceneLimits.maxImageRenderPassTotalPixels) + 1),
        ]
        for cost in costs {
            XCTAssertTrue(
                RetainedLazyListRemovalPaint.fittingSceneBudget(
                    values, liveCost: cost, surfaceSize: IntSize(width: 8, height: 8), displayScale: 1
                ).isEmpty)
        }
    }

    func testBackdropSourceCannotBorrowAResizedTargetDomain() async throws {
        let dependent = try paint(extent: 8, dependent: true)
        XCTAssertTrue(dependent.permitsTargetSize(IntSize(width: 8, height: 8)))
        for size in [IntSize(width: 4, height: 8), IntSize(width: 16, height: 8)] {
            XCTAssertFalse(dependent.permitsTargetSize(size))
            let selected = RetainedLazyListRemovalPaint.fittingSceneBudget(
                [dependent], liveCost: .init(passCount: 0, pixelCount: 0), surfaceSize: size, displayScale: 1)
            XCTAssertTrue(selected.isEmpty)
            var result = GPUIScene(clearColor: .clear)
            dependent.append(to: &result, targetSize: size, displayScale: 1)
            XCTAssertEqual(result.primitiveCount, 0)
            XCTAssertTrue(result.imageRenderPasses.isEmpty)
        }
    }

    func testDisjointFrameRangesKeepTheirOwnClipStackAndExcludeSiblingPaint() async throws {
        let firstClip = Rect(x: 0, y: 0, width: 4, height: 4)
        let secondClip = Rect(x: 8, y: 0, width: 4, height: 4)
        let fill = Rect(x: 0, y: 0, width: 12, height: 4)
        let frame = RenderFrame(
            commands: [
                .pushClip(ClipCommand(shape: .rect(firstClip, cornerRadius: 0))),
                .fillRect(FillRectCommand(rect: fill, color: Color(red: 1, green: 0, blue: 0))),
                .popClip,
                .pushClip(ClipCommand(shape: .rect(secondClip, cornerRadius: 0))),
                .fillRect(FillRectCommand(rect: fill, color: Color(red: 0, green: 0, blue: 1))),
                .popClip,
                .fillRect(FillRectCommand(rect: fill, color: Color(red: 0, green: 1, blue: 0))),
            ])
        let snapshot = RetainedLazyListPaintSnapshot(
            content: .frame(frame), identity: PaintSnapshotIdentity(),
            surfaceSize: IntSize(width: 16, height: 16), displayScale: 1)
        guard case .captured(let source) = snapshot.capture([1..<2, 4..<5]) else {
            return XCTFail("Expected both selected spans without their green sibling")
        }
        XCTAssertEqual(source.recordCount, 2)
        XCTAssertEqual(source.scene.layers[0].quads.map(\.startG), [0, 0])
        XCTAssertEqual(source.scene.layers[0].quads.map { $0.contentMask.bounds }, [firstClip, secondClip])
    }

    func testReservedCommandsAndUnsupportedFrameClipsAreNotEmptyCaptures() async {
        let rect = Rect(x: 0, y: 0, width: 8, height: 8)
        let fill = RenderCommand.fillRect(FillRectCommand(rect: rect, color: .white))
        let candidates: [[RenderCommand]] = [
            [.drawText(DrawTextCommand(text: "Retired", position: .zero))],
            [.applyBlur(BlurCommand(region: rect, radius: 2))],
            [.pushClip(ClipCommand(shape: .rect(rect, cornerRadius: 2))), fill, .popClip],
            [
                .pushClip(ClipCommand(shape: .ellipse(center: Point(x: 4, y: 4), radiusX: 4, radiusY: 4))), fill,
                .popClip,
            ],
            [.pushClip(ClipCommand(shape: .path(RenderPath()))), fill, .popClip],
        ]
        for commands in candidates {
            let frame = RenderFrame(commands: commands)
            XCTAssertFalse(RetainedLazyListPaintSnapshot.permitsFrameSceneLowering(frame))
            let snapshot = RetainedLazyListPaintSnapshot(
                content: .frame(frame), identity: PaintSnapshotIdentity(),
                surfaceSize: IntSize(width: 16, height: 16), displayScale: 1)
            guard case .unsupported = snapshot.capture([0..<commands.count]) else {
                XCTFail("An unsupported command or clip must not become empty paint")
                continue
            }
        }
    }
}
