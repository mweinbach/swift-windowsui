import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

final class PrepaintSnapshotReplayTests: XCTestCase {
    func testScrolledOutDescendantRebuildsAfterFocusOrderShrinksOnBothRenderPaths() async {
        await MainActor.run {
            for usesScene in [false, true] {
                var activations = 0
                let marker = ViewNode(
                    frame: Rect(x: 10, y: 5, width: 30, height: 30),
                    backgroundColor: .white,
                    isFocusable: true)
                marker.onActivate = { activations += 1 }
                let branch = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 80, height: 40),
                    isHitTestVisible: false,
                    children: [marker])
                // Keep the later dispatch/interaction streams long enough to
                // contain the old numeric range. Only the focus stream shrinks,
                // reproducing the original replay crash rather than relying on
                // every stream becoming shorter at once.
                let laterRows = (0..<8).map { index in
                    ViewNode(frame: Rect(x: 0, y: 200 + Double(index) * 5, width: 80, height: 5))
                }
                let content = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 400),
                    isHitTestVisible: false,
                    children: [branch] + laterRows)
                let scroller = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 100),
                    clipsToBounds: true,
                    scrollAxis: .vertical,
                    children: [content])
                let root = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 100),
                    isHitTestVisible: false,
                    children: [scroller])
                let runtime = RetainedViewRuntime(root: root)
                let render: @MainActor () -> Void = {
                    if usesScene {
                        _ = runtime.renderScene()
                    } else {
                        _ = runtime.renderFrame()
                    }
                }
                render()
                let initialRange = marker.cachedPrepaintRange
                XCTAssertNotNil(initialRange)

                scroller.scrollOffset = 200
                render()
                XCTAssertEqual(
                    marker.cachedPrepaintRange, initialRange,
                    "The culled branch leaves its descendant untouched")

                scroller.scrollOffset = 0
                render()
                XCTAssertNotEqual(marker.cachedPrepaintRange?.generation, initialRange?.generation)

                root.backgroundColor = .black
                render()
                XCTAssertGreaterThan(runtime.lastPrepaintReplayCount, 0, "Current clean ranges still replay")
                runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
                XCTAssertTrue(runtime.focusedNode === marker)
                runtime.pointerDown(at: Point(x: 20, y: 20))
                runtime.pointerUp(at: Point(x: 20, y: 20))
                XCTAssertEqual(activations, 1)
            }
        }
    }

    func testAncestorReplayDoesNotRebaseAHiddenDescendantsOlderSnapshot() async {
        await MainActor.run {
            let prefix = ViewNode(
                frame: Rect(x: 120, y: 0, width: 30, height: 30), isFocusable: true)
            let marker = ViewNode(
                frame: Rect(x: 10, y: 5, width: 30, height: 30),
                backgroundColor: .white,
                isFocusable: true)
            let branch = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                isHitTestVisible: false,
                children: [marker])
            let container = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isHitTestVisible: false,
                children: [branch])
            let runtime = RetainedViewRuntime(
                root: ViewNode(
                    frame: Rect(x: 0, y: 0, width: 160, height: 100),
                    isHitTestVisible: false,
                    children: [prefix, container]))
            _ = runtime.renderScene()
            let initialRange = marker.cachedPrepaintRange
            XCTAssertNotNil(initialRange)

            branch.isHidden = true
            _ = runtime.renderFrame()
            prefix.isHidden = true
            _ = runtime.renderScene()
            XCTAssertGreaterThan(runtime.lastPrepaintReplayCount, 0, "The unchanged container should replay")
            XCTAssertEqual(
                marker.cachedPrepaintRange, initialRange,
                "A hidden descendant was not copied, so its old range must not be shifted or restamped")

            branch.isHidden = false
            _ = runtime.renderFrame()
            XCTAssertNotEqual(marker.cachedPrepaintRange?.generation, initialRange?.generation)
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
            XCTAssertTrue(runtime.focusedNode === marker)
        }
    }

    func testOpacityCycleRestoresDescendantPixelsOnBothRenderPaths() async {
        await MainActor.run {
            let white = Color(red: 1, green: 1, blue: 1, alpha: 1)
            let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
            let black = Color(red: 0, green: 0, blue: 0, alpha: 1)
            for usesScene in [false, true] {
                for paintsSibling in [false, true] {
                    let marker = ViewNode(
                        frame: Rect(x: 10, y: 5, width: 30, height: 30),
                        backgroundColor: white,
                        isFocusable: true)
                    let branch = ViewNode(
                        frame: Rect(x: 0, y: 0, width: 80, height: 40), children: [marker])
                    var children = [branch]
                    if paintsSibling {
                        children.append(
                            ViewNode(
                                frame: Rect(x: 90, y: 5, width: 30, height: 30), backgroundColor: blue))
                    }
                    let runtime = RetainedViewRuntime(
                        clearColor: black,
                        root: ViewNode(frame: Rect(x: 0, y: 0, width: 160, height: 80), children: children))
                    let label = "\(usesScene ? "scene" : "frame"), painted sibling: \(paintsSibling)"
                    let initial = Self.paintBitmap(runtime, usesScene: usesScene)
                    Self.assertPixel(initial, x: 20, y: 15, color: white, label)
                    Self.assertPixel(initial, x: 100, y: 15, color: paintsSibling ? blue : black, label)

                    // Prepaint can visit the marker while paint culls this
                    // ancestor. Its prepaint generation cannot establish that
                    // its older paint range belongs to the new output.
                    branch.opacity = 0
                    let transparent = Self.paintBitmap(runtime, usesScene: usesScene)
                    Self.assertPixel(transparent, x: 20, y: 15, color: black, label)
                    Self.assertPixel(transparent, x: 100, y: 15, color: paintsSibling ? blue : black, label)

                    // Without a sibling the stale frame range can exceed the
                    // previous command buffer. With one, a numerically valid
                    // range can replay the sibling instead of the white child.
                    branch.opacity = 1
                    let restored = Self.paintBitmap(runtime, usesScene: usesScene)
                    Self.assertPixel(restored, x: 20, y: 15, color: white, label)
                    Self.assertPixel(restored, x: 100, y: 15, color: paintsSibling ? blue : black, label)
                    Self.assertPixel(restored, x: 5, y: 15, color: black, label)
                    Self.assertPixel(restored, x: 45, y: 15, color: black, label)
                }
            }
        }
    }

    func testAncestorPaintReplayDoesNotRebaseAnOpacityCulledDescendantsOlderRange() async {
        await MainActor.run {
            let white = Color(red: 1, green: 1, blue: 1, alpha: 1)
            let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
            let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
            let black = Color(red: 0, green: 0, blue: 0, alpha: 1)
            for usesScene in [false, true] {
                let prefix = ViewNode(
                    frame: Rect(x: 120, y: 5, width: 30, height: 30), backgroundColor: green)
                let marker = ViewNode(
                    frame: Rect(x: 10, y: 5, width: 30, height: 30), backgroundColor: white)
                let branch = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 80, height: 40), children: [marker])
                let currentSibling = ViewNode(
                    frame: Rect(x: 60, y: 5, width: 30, height: 30), backgroundColor: blue)
                let container = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 60), children: [branch, currentSibling])
                let runtime = RetainedViewRuntime(
                    clearColor: black,
                    root: ViewNode(
                        frame: Rect(x: 0, y: 0, width: 160, height: 80), children: [prefix, container]))
                let label = usesScene ? "scene" : "frame"
                let initial = Self.paintBitmap(runtime, usesScene: usesScene)
                Self.assertPixel(initial, x: 20, y: 15, color: white, label)
                Self.assertPixel(initial, x: 70, y: 15, color: blue, label)
                Self.assertPixel(initial, x: 130, y: 15, color: green, label)
                let originalRange = usesScene ? marker.cachedScenePaintRange : marker.cachedFrameCommandRange
                XCTAssertNotNil(originalRange, label)

                branch.opacity = 0
                let transparent = Self.paintBitmap(runtime, usesScene: usesScene)
                Self.assertPixel(transparent, x: 20, y: 15, color: black, label)
                Self.assertPixel(transparent, x: 70, y: 15, color: blue, label)

                // Removing preceding paint rebases the clean container's
                // copied ranges. Its blue child belongs to the source
                // snapshot; the hidden white descendant was not copied.
                prefix.isHidden = true
                let rebased = Self.paintBitmap(runtime, usesScene: usesScene)
                XCTAssertGreaterThan(
                    usesScene ? runtime.lastSceneReplayCount : runtime.lastFrameReplayCount, 0,
                    "The current clean container must still replay on the \(label) path")
                XCTAssertEqual(
                    usesScene ? marker.cachedScenePaintRange : marker.cachedFrameCommandRange,
                    originalRange,
                    "Ancestor replay must not shift a descendant's older paint range on the \(label) path")
                Self.assertPixel(rebased, x: 20, y: 15, color: black, label)
                Self.assertPixel(rebased, x: 70, y: 15, color: blue, label)
                Self.assertPixel(rebased, x: 130, y: 15, color: black, label)

                branch.opacity = 1
                let restored = Self.paintBitmap(runtime, usesScene: usesScene)
                Self.assertPixel(restored, x: 20, y: 15, color: white, label)
                Self.assertPixel(restored, x: 70, y: 15, color: blue, label)
                Self.assertPixel(restored, x: 130, y: 15, color: black, label)
                XCTAssertGreaterThan(
                    usesScene ? runtime.lastSceneReplayCount : runtime.lastFrameReplayCount, 0,
                    "The unaffected blue child must remain eligible for replay on the \(label) path")
            }
        }
    }

    @MainActor
    private static func paintBitmap(_ runtime: RetainedViewRuntime, usesScene: Bool) -> BitmapSurface {
        let size = IntSize(width: 160, height: 80)
        if usesScene {
            return GPUIRawSceneRasterizer.rasterize(runtime.renderScene(), size: size)
        }
        return GPUIRawSceneRasterizer.rasterize(runtime.renderFrame(), size: size)
    }

    private static func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, color: Color, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        XCTAssertEqual(
            Float(bitmap.pixels[offset + 2]) / 255, color.red, accuracy: 1 / 255,
            "\(message): red at (\(x), \(y))", file: file, line: line)
        XCTAssertEqual(
            Float(bitmap.pixels[offset + 1]) / 255, color.green, accuracy: 1 / 255,
            "\(message): green at (\(x), \(y))", file: file, line: line)
        XCTAssertEqual(
            Float(bitmap.pixels[offset]) / 255, color.blue, accuracy: 1 / 255,
            "\(message): blue at (\(x), \(y))", file: file, line: line)
        XCTAssertEqual(
            Float(bitmap.pixels[offset + 3]) / 255, color.alpha, accuracy: 1 / 255,
            "\(message): alpha at (\(x), \(y))", file: file, line: line)
    }
}
