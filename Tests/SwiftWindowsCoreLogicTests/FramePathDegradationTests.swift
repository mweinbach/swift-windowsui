import SwiftWindowsCore
import SwiftWindowsDemo
import SwiftWindowsGraphics
import WinSwiftUI
import XCTest

/// Phase 6 frame fallback policy — readable degradation of the frame command
/// stream. `D3D11Renderer` (the frame fallback backend) paints `fillRect` +
/// `drawBitmap` only; `FramePathDegradation` rewrites vector path commands as
/// CPU-rasterized bitmaps so Canvas drawing, `backgroundPath` chrome, and the
/// SF-symbol vector fallback stay visible in a downgraded session instead of
/// being soft-skipped.
@MainActor
final class FramePathDegradationTests: XCTestCase {

    private func visiblePixelCount(_ bitmap: BitmapSurface) -> Int {
        var count = 0
        var offset = 3
        while offset < bitmap.pixels.count {
            if bitmap.pixels[offset] > 0 {
                count += 1
            }
            offset += 4
        }
        return count
    }

    private func drawBitmapCommands(in frame: RenderFrame) -> [DrawBitmapCommand] {
        frame.commands.compactMap { command in
            guard case .drawBitmap(let bitmapCommand) = command else { return nil }
            return bitmapCommand
        }
    }

    private func pathCommandCount(in frame: RenderFrame) -> Int {
        frame.commands.reduce(0) { count, command in
            switch command {
            case .fillPath, .strokePath:
                return count + 1
            default:
                return count
            }
        }
    }

    func testFrameWithoutPathCommandsPassesThroughUnchanged() async {
        let frame = RenderFrame(
            clearColor: .black,
            commands: [
                .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 20, height: 20), color: .red)),
                .pushClip(ClipCommand(shape: .rect(Rect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0))),
                .popClip,
            ]
        )

        let degraded = FramePathDegradation.degradingPathsToBitmaps(in: frame)
        XCTAssertEqual(degraded, frame, "Frames without path commands must pass through untouched")
    }

    func testFillPathDegradesToDrawBitmapWithVisiblePixels() async {
        var path = RenderPath()
        path.move(to: Point(x: 10, y: 10))
        path.addLine(to: Point(x: 60, y: 10))
        path.addLine(to: Point(x: 35, y: 50))
        path.close()

        let frame = RenderFrame(
            commands: [
                .fillPath(FillPathCommand(path: path, color: Color(red: 1, green: 0, blue: 0, alpha: 1)))
            ]
        )

        let degraded = FramePathDegradation.degradingPathsToBitmaps(in: frame)
        XCTAssertEqual(degraded.commands.count, 1)
        guard case .drawBitmap(let bitmapCommand) = degraded.commands.first else {
            XCTFail("fillPath should degrade to drawBitmap")
            return
        }
        XCTAssertGreaterThan(
            visiblePixelCount(bitmapCommand.bitmap), 0,
            "Rasterized path bitmap must contain painted pixels")
        XCTAssertEqual(bitmapCommand.rect.minX, 10, accuracy: 1.5)
        XCTAssertEqual(bitmapCommand.rect.minY, 10, accuracy: 1.5)
        XCTAssertEqual(bitmapCommand.opacity, 1, accuracy: 0.001)
    }

    func testStrokePathWithZeroHeightBoundsDegradesToVisibleBitmap() async {
        // A straight horizontal line has zero-height segment bounds; the
        // stroke outset must still produce a paintable footprint (mirrors
        // ScenePainter's strokeBounds handling).
        var path = RenderPath()
        path.move(to: Point(x: 10, y: 10))
        path.addLine(to: Point(x: 110, y: 10))

        let frame = RenderFrame(
            commands: [
                .strokePath(
                    StrokePathCommand(
                        path: path,
                        color: Color(red: 0, green: 0, blue: 1, alpha: 1),
                        style: StrokeStyle(lineWidth: 4)
                    ))
            ]
        )

        let degraded = FramePathDegradation.degradingPathsToBitmaps(in: frame)
        XCTAssertEqual(degraded.commands.count, 1)
        guard case .drawBitmap(let bitmapCommand) = degraded.commands.first else {
            XCTFail("strokePath should degrade to drawBitmap")
            return
        }
        XCTAssertGreaterThan(visiblePixelCount(bitmapCommand.bitmap), 0)
        XCTAssertEqual(bitmapCommand.rect.minY, 8, accuracy: 1.5, "Stroke outset should center the bitmap on the line")
        XCTAssertGreaterThanOrEqual(bitmapCommand.bitmap.height, 4)
    }

    func testClipRectIsPreservedAndBakedIntoRasterizedBitmap() async {
        var path = RenderPath()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 100, y: 0))
        path.addLine(to: Point(x: 100, y: 100))
        path.addLine(to: Point(x: 0, y: 100))
        path.close()

        let clip = Rect(x: 40, y: 40, width: 20, height: 20)
        let frame = RenderFrame(
            commands: [
                .fillPath(
                    FillPathCommand(path: path, color: Color(red: 0, green: 1, blue: 0, alpha: 1), clipRect: clip))
            ]
        )

        let degraded = FramePathDegradation.degradingPathsToBitmaps(in: frame)
        guard case .drawBitmap(let bitmapCommand) = degraded.commands.first else {
            XCTFail("fillPath should degrade to drawBitmap")
            return
        }
        XCTAssertEqual(bitmapCommand.clipRect, clip, "Per-command clip must survive degradation")
        XCTAssertEqual(bitmapCommand.rect.minX, 40, accuracy: 1.5, "Rasterization is masked to the clip")
        XCTAssertEqual(bitmapCommand.rect.minY, 40, accuracy: 1.5)
        XCTAssertLessThanOrEqual(bitmapCommand.bitmap.width, 22)
        XCTAssertLessThanOrEqual(bitmapCommand.bitmap.height, 22)
        XCTAssertGreaterThan(visiblePixelCount(bitmapCommand.bitmap), 0)
    }

    func testTransparentAndDegeneratePathsAreDropped() async {
        var path = RenderPath()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 10, y: 10))

        let frame = RenderFrame(
            commands: [
                .fillPath(FillPathCommand(path: path, color: .clear)),
                .strokePath(
                    StrokePathCommand(path: path, color: .red, style: StrokeStyle(lineWidth: 0))),
                .fillPath(FillPathCommand(path: RenderPath(), color: .red)),
            ]
        )

        let degraded = FramePathDegradation.degradingPathsToBitmaps(in: frame)
        XCTAssertTrue(
            degraded.commands.isEmpty,
            "Transparent, zero-width, and empty paths have no paintable footprint and must drop")
    }

    func testPresentationOrderIsPreservedAroundDegradedPaths() async {
        var path = RenderPath()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 8, y: 0))
        path.addLine(to: Point(x: 8, y: 8))
        path.close()

        let frame = RenderFrame(
            commands: [
                .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 4, height: 4), color: .red)),
                .fillPath(FillPathCommand(path: path, color: .green)),
                .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 4, height: 4), color: .blue)),
            ]
        )

        let degraded = FramePathDegradation.degradingPathsToBitmaps(in: frame)
        XCTAssertEqual(degraded.commands.count, 3)
        guard case .fillRect(let first) = degraded.commands[0],
            case .drawBitmap = degraded.commands[1],
            case .fillRect(let third) = degraded.commands[2]
        else {
            XCTFail("Degradation must preserve presentation order")
            return
        }
        XCTAssertEqual(first.color, .red)
        XCTAssertEqual(third.color, .blue)
    }

    func testScaleFactorRasterizesInDevicePixels() async {
        var path = RenderPath()
        path.move(to: Point(x: 10, y: 10))
        path.addLine(to: Point(x: 20, y: 10))
        path.addLine(to: Point(x: 20, y: 20))
        path.addLine(to: Point(x: 10, y: 20))
        path.close()

        let frame = RenderFrame(
            commands: [
                .fillPath(FillPathCommand(path: path, color: .white))
            ]
        )

        let degraded = FramePathDegradation.degradingPathsToBitmaps(in: frame, scaleFactor: 2.0)
        guard case .drawBitmap(let bitmapCommand) = degraded.commands.first else {
            XCTFail("fillPath should degrade to drawBitmap")
            return
        }
        XCTAssertEqual(bitmapCommand.bitmap.width, 20, "10 logical px at 2x must rasterize as 20 device px")
        XCTAssertEqual(bitmapCommand.bitmap.height, 20)
        XCTAssertEqual(bitmapCommand.rect.minX, 10, accuracy: 0.75, "Draw origin stays in logical coordinates")
        XCTAssertEqual(bitmapCommand.rect.minY, 10, accuracy: 0.75)
    }

    func testUnpaintableCommandsAfterDegradationReportsOnlyReservedCommands() async {
        var path = RenderPath()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 8, y: 8))

        let frame = RenderFrame(
            commands: [
                .fillPath(FillPathCommand(path: path, color: .white)),
                .applyBlur(BlurCommand(region: Rect(x: 0, y: 0, width: 10, height: 10), radius: 4)),
                .drawText(DrawTextCommand(text: "hi", position: Point(x: 0, y: 0))),
                .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 4, height: 4), color: .red)),
            ]
        )

        let unpaintable = FramePathDegradation.unpaintableCommandsAfterDegradation(in: frame)
        XCTAssertEqual(unpaintable.count, 2)
        XCTAssertEqual(pathCommandCount(in: frame), 1)
        XCTAssertEqual(
            pathCommandCount(in: FramePathDegradation.degradingPathsToBitmaps(in: frame)), 0,
            "Degraded frames must contain no residual path commands")
    }

    /// End-to-end contract for the shared demo: every command the retained
    /// runtime delivers to the frame backend for every screen, including the
    /// component gallery, is paintable after degradation — nothing a supported
    /// screen needs is silently dropped on the frame path. Iterating all cases
    /// keeps newly added demo screens covered without another hard-coded list.
    func testDemoScreensDegradeToFullyPaintableFrameCommandStreams() async {
        for screen in DemoScreen.allCases {
            let model = DemoDashboardModel()
            model.selectedScreen = screen
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: DemoRootView(model: model),
                size: IntSize(width: 1280, height: 720),
                displayScale: 1.0
            )

            XCTAssertFalse(
                snapshot.frame.commands.isEmpty,
                "\(screen) frame should contain paint commands")
            XCTAssertTrue(
                FramePathDegradation.unpaintableCommandsAfterDegradation(in: snapshot.frame).isEmpty,
                "\(screen) frame must be fully paintable on the fillRect+drawBitmap frame backend")
            XCTAssertEqual(
                pathCommandCount(in: FramePathDegradation.degradingPathsToBitmaps(in: snapshot.frame)), 0,
                "\(screen) degraded frame must not retain path commands")
            XCTAssertFalse(
                drawBitmapCommands(in: FramePathDegradation.degradingPathsToBitmaps(in: snapshot.frame)).isEmpty,
                "\(screen) frame should carry text/content bitmaps so it stays readable")
        }
    }
}
