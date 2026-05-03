import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import SwiftWindowsPlatform
@testable import SwiftWindowsUI

final class RetainedViewRuntimeTests: XCTestCase {
    func testVerticalStackLayoutUsesPaddingAlignmentAndMainAlignment() async {
        await MainActor.run {
            let first = ViewNode(
                backgroundColor: .white,
                preferredSize: Size(width: 20, height: 10)
            )
            let second = ViewNode(
                backgroundColor: .black,
                preferredSize: Size(width: 40, height: 20)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                layoutMode: .stack(
                    .vertical(
                        spacing: 5,
                        padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10),
                        alignment: .center,
                        mainAlignment: .end
                    )
                ),
                isHitTestVisible: false,
                children: [first, second]
            )
            let runtime = RetainedViewRuntime(root: root)

            XCTAssertEqual(
                fillRectCommands(in: runtime.renderFrame()).map(\.rect),
                [
                    Rect(x: 40, y: 55, width: 20, height: 10),
                    Rect(x: 30, y: 70, width: 40, height: 20),
                ]
            )
        }
    }

    func testHorizontalStackDistributesExtraWidthToHigherPriorityChild() async {
        await MainActor.run {
            let first = ViewNode(
                backgroundColor: .white,
                preferredSize: Size(width: 20, height: 20)
            )
            let second = ViewNode(
                backgroundColor: .black,
                preferredSize: Size(width: 20, height: 20),
                layoutPriority: 1
            )
            let third = ViewNode(
                backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                preferredSize: Size(width: 20, height: 20)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 40),
                layoutMode: .stack(.horizontal(spacing: 10, alignment: .center)),
                isHitTestVisible: false,
                children: [first, second, third]
            )
            let runtime = RetainedViewRuntime(root: root)

            XCTAssertEqual(
                fillRectCommands(in: runtime.renderFrame()).map(\.rect),
                [
                    Rect(x: 0, y: 10, width: 20, height: 20),
                    Rect(x: 30, y: 10, width: 60, height: 20),
                    Rect(x: 100, y: 10, width: 20, height: 20),
                ]
            )
        }
    }

    func testHorizontalStackShrinksLowerPriorityChildFirst() async {
        await MainActor.run {
            let first = ViewNode(
                backgroundColor: .white,
                preferredSize: Size(width: 50, height: 20)
            )
            let second = ViewNode(
                backgroundColor: .black,
                preferredSize: Size(width: 50, height: 20),
                layoutPriority: 1
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40),
                layoutMode: .stack(.horizontal(spacing: 10, alignment: .center)),
                isHitTestVisible: false,
                children: [first, second]
            )
            let runtime = RetainedViewRuntime(root: root)

            XCTAssertEqual(
                fillRectCommands(in: runtime.renderFrame()).map(\.rect),
                [
                    Rect(x: 0, y: 10, width: 40, height: 20),
                    Rect(x: 50, y: 10, width: 50, height: 20),
                ]
            )
        }
    }

    func testClippingPreventsPointerHitsOutsideParentBounds() async {
        await MainActor.run {
            var activations = 0

            let child = ViewNode(frame: Rect(x: 40, y: 40, width: 20, height: 20))
            child.onActivate = { activations += 1 }

            let clippedParent = ViewNode(
                frame: Rect(x: 10, y: 10, width: 50, height: 50),
                clipsToBounds: true,
                isHitTestVisible: false,
                children: [child]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isHitTestVisible: false,
                children: [clippedParent]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.pointerDown(at: Point(x: 65, y: 65))
            runtime.pointerUp(at: Point(x: 65, y: 65))
            runtime.pointerDown(at: Point(x: 55, y: 55))
            runtime.pointerUp(at: Point(x: 55, y: 55))

            XCTAssertEqual(activations, 1)
        }
    }

    func testTabFocusSkipsHiddenNodesLoopsAndActivatesFocusedNode() async {
        await MainActor.run {
            var focusEvents: [String] = []
            var activations: [String] = []

            let hidden = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10), isFocusable: true, isHidden: true)

            let first = ViewNode(frame: Rect(x: 10, y: 0, width: 10, height: 10), isFocusable: true)
            first.onFocusEnter = { focusEvents.append("first+") }
            first.onFocusExit = { focusEvents.append("first-") }
            first.onActivate = { activations.append("first") }

            let second = ViewNode(frame: Rect(x: 20, y: 0, width: 10, height: 10), isFocusable: true)
            second.onFocusEnter = { focusEvents.append("second+") }
            second.onFocusExit = { focusEvents.append("second-") }
            second.onActivate = { activations.append("second") }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40),
                isHitTestVisible: false,
                children: [hidden, first, second]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue, modifiers: [.shift]))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(
                focusEvents,
                ["first+", "first-", "second+", "second-", "first+", "first-"]
            )
            XCTAssertEqual(activations, ["first", "second"])
        }
    }

    func testTextInputRoutesToFocusedNode() async {
        await MainActor.run {
            var receivedText: [String] = []
            var receivedKeys: [KeyboardKey?] = []

            let field = ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 24), isFocusable: true)
            field.onTextInput = { receivedText.append($0) }
            field.onKeyDown = { receivedKeys.append($0.key) }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40),
                isHitTestVisible: false,
                children: [field]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.textInput("ignored")
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
            runtime.textInput("A")
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.backspace.rawValue))

            XCTAssertEqual(receivedText, ["A"])
            XCTAssertEqual(receivedKeys, [.backspace])
        }
    }

    func testPointerUpInsideAndOutsideCallMatchingHandlers() async {
        await MainActor.run {
            var pointerDownCount = 0
            var insideCount = 0
            var outsideCount = 0
            var activationCount = 0

            let target = ViewNode(frame: Rect(x: 10, y: 10, width: 20, height: 20))
            target.onPointerDown = { pointerDownCount += 1 }
            target.onPointerUpInside = { insideCount += 1 }
            target.onPointerUpOutside = { outsideCount += 1 }
            target.onActivate = { activationCount += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isHitTestVisible: false,
                children: [target]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.pointerDown(at: Point(x: 15, y: 15))
            runtime.pointerUp(at: Point(x: 16, y: 16))
            runtime.pointerDown(at: Point(x: 15, y: 15))
            runtime.pointerUp(at: Point(x: 80, y: 80))

            XCTAssertEqual(pointerDownCount, 2)
            XCTAssertEqual(insideCount, 1)
            XCTAssertEqual(outsideCount, 1)
            XCTAssertEqual(activationCount, 1)
        }
    }

    func testRenderFrameCapturesButtonVisualStateChanges() async {
        await MainActor.run {
            let palette = SurfacePalette(
                idle: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                focused: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                pressed: Color(red: 0.5, green: 0.6, blue: 0.7, alpha: 1),
                activated: Color(red: 0.7, green: 0.8, blue: 0.9, alpha: 1)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                isHitTestVisible: false
            )
            let runtime = RetainedViewRuntime(root: root)
            let button = Controls.button(
                runtime: runtime,
                frame: Rect(x: 10, y: 8, width: 30, height: 16),
                cornerRadius: 4,
                palette: palette,
                chrome: SurfaceChrome(),
                animation: ControlAnimationStyle(focusDuration: 0, pressDuration: 0, activationDuration: 0)
            )
            root.addChild(button)

            XCTAssertEqual(
                fillRectCommands(in: runtime.renderFrame()),
                [
                    FillRectCommand(
                        rect: Rect(x: 10, y: 8, width: 30, height: 16),
                        color: palette.idle,
                        cornerRadius: 4
                    )
                ]
            )

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))

            XCTAssertEqual(
                fillRectCommands(in: runtime.renderFrame()),
                [
                    FillRectCommand(
                        rect: Rect(x: 10, y: 8, width: 30, height: 16),
                        color: palette.focused,
                        cornerRadius: 4
                    )
                ]
            )

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(
                fillRectCommands(in: runtime.renderFrame()),
                [
                    FillRectCommand(
                        rect: Rect(x: 10, y: 8, width: 30, height: 16),
                        color: palette.activated,
                        cornerRadius: 4
                    )
                ]
            )
        }
    }

    func testAnimateColorInterpolatesAndCompletes() async {
        await MainActor.run {
            let node = ViewNode(backgroundColor: .black)
            let runtime = RetainedViewRuntime(root: node)

            runtime.animateColor(.background, of: node, to: .white, duration: 2, at: 10)

            XCTAssertTrue(runtime.hasActiveAnimations)
            XCTAssertEqual(node.backgroundColor, .black)
            XCTAssertTrue(runtime.tickAnimations(at: 11))
            XCTAssertEqual(node.backgroundColor, Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            XCTAssertTrue(runtime.tickAnimations(at: 12))
            XCTAssertEqual(node.backgroundColor, .white)
            XCTAssertFalse(runtime.hasActiveAnimations)
            XCTAssertFalse(runtime.tickAnimations(at: 13))
        }
    }

    func testMouseWheelScrollsNearestScrollableAncestorAndClampsOffset() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 30))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 30))
            let itemC = ViewNode(backgroundColor: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1), preferredSize: Size(width: 60, height: 30))

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 70),
                layoutMode: .stack(.vertical(spacing: 10, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))),
                scrollAxis: .vertical,
                scrollStep: 20,
                showsScrollIndicator: true,
                isHitTestVisible: false,
                children: [itemA, itemB, itemC]
            )
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [scrollPanel])
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
            XCTAssertEqual(scrollPanel.scrollOffset, 20)

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -10)
            XCTAssertEqual(scrollPanel.scrollOffset, 60)

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: 10)
            XCTAssertEqual(scrollPanel.scrollOffset, 0)
        }
    }

    func testRenderFrameAppliesScrollOffsetAndDrawsScrollIndicator() async {
        await MainActor.run {
            let indicatorColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 0.3)
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 30))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 30))
            let itemC = ViewNode(backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1), preferredSize: Size(width: 60, height: 30))

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 70),
                layoutMode: .stack(.vertical(spacing: 10, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                scrollIndicatorColor: indicatorColor,
                isHitTestVisible: false,
                children: [itemA, itemB, itemC]
            )
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [scrollPanel])
            let runtime = RetainedViewRuntime(root: root)

            let fills = fillRectCommands(in: runtime.renderFrame())

            XCTAssertEqual(fills[0].rect, Rect(x: 20, y: 0, width: 60, height: 30))
            XCTAssertEqual(fills[1].rect, Rect(x: 20, y: 40, width: 60, height: 30))
            XCTAssertEqual(fills[2].rect, Rect(x: 20, y: 80, width: 60, height: 30))
            XCTAssertEqual(fills.last?.color, indicatorColor)
        }
    }

    func testLargeScrollPanelCullsOffscreenRowsFromRenderFrame() async {
        await MainActor.run {
            let rows = (0..<500).map { index in
                ViewNode(
                    backgroundColor: index.isMultiple(of: 2) ? .white : .black,
                    preferredSize: Size(width: 100, height: 20)
                )
            }
            let scrollPanel = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                clipsToBounds: true,
                layoutMode: .stack(.vertical(spacing: 2, alignment: .stretch)),
                scrollAxis: .vertical,
                scrollOffset: 4_000,
                showsScrollIndicator: true,
                isHitTestVisible: false,
                children: rows
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                isHitTestVisible: false,
                children: [scrollPanel]
            )
            let runtime = RetainedViewRuntime(root: root)

            let fills = fillRectCommands(in: runtime.renderFrame())

            XCTAssertLessThan(fills.count, 40)
            XCTAssertGreaterThan(fills.count, 2)
            XCTAssertTrue(fills.allSatisfy { $0.rect.intersected(with: scrollPanel.frame) != nil })
        }
    }

    func testGridLayoutPlacesChildrenInRowsAndColumns() async {
        await MainActor.run {
            let children = [
                ViewNode(backgroundColor: .white, preferredSize: Size(width: 20, height: 10)),
                ViewNode(backgroundColor: .black, preferredSize: Size(width: 20, height: 30)),
                ViewNode(
                    backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                    preferredSize: Size(width: 20, height: 15)
                ),
            ]
            let grid = ViewNode(
                frame: Rect(x: 0, y: 0, width: 110, height: 80),
                layoutMode: .grid(GridLayout(columns: 2, rowSpacing: 5, columnSpacing: 10)),
                children: children
            )
            let runtime = RetainedViewRuntime(root: grid)

            runtime.setRootSize(IntSize(width: 110, height: 80))
            _ = runtime.renderFrame()

            XCTAssertEqual(children[0].resolvedFrame, Rect(x: 0, y: 0, width: 50, height: 30))
            XCTAssertEqual(children[1].resolvedFrame, Rect(x: 60, y: 0, width: 50, height: 30))
            XCTAssertEqual(children[2].resolvedFrame, Rect(x: 0, y: 35, width: 50, height: 15))
        }
    }

    func testGridLayoutUsesResolvedColumnWidths() async {
        await MainActor.run {
            let first = ViewNode(backgroundColor: .white, preferredSize: Size(width: 20, height: 10))
            let second = ViewNode(backgroundColor: .black, preferredSize: Size(width: 20, height: 20))
            let third = ViewNode(
                backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                preferredSize: Size(width: 20, height: 15)
            )
            let grid = ViewNode(
                frame: Rect(x: 0, y: 0, width: 150, height: 90),
                layoutMode: .grid(GridLayout(columns: 3, rowSpacing: 4, columnSpacing: 6, columnWidths: [20, 40, 60])),
                children: [first, second, third]
            )
            let runtime = RetainedViewRuntime(root: grid)

            runtime.setRootSize(IntSize(width: 150, height: 90))
            _ = runtime.renderFrame()

            XCTAssertEqual(first.resolvedFrame, Rect(x: 0, y: 0, width: 20, height: 20))
            XCTAssertEqual(second.resolvedFrame, Rect(x: 26, y: 0, width: 40, height: 20))
            XCTAssertEqual(third.resolvedFrame, Rect(x: 72, y: 0, width: 60, height: 20))
        }
    }

    func testScrollIndicatorHoverAndDragUpdateColorAndOffset() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 30))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 30))
            let itemC = ViewNode(backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1), preferredSize: Size(width: 60, height: 30))

            let idleColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 0.3)
            let hoverColor = Color(red: 0.9, green: 0.95, blue: 1, alpha: 0.55)
            let activeColor = Color(red: 1, green: 1, blue: 1, alpha: 0.8)

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 70),
                layoutMode: .stack(.vertical(spacing: 10, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))),
                scrollAxis: .vertical,
                showsScrollIndicator: true,
                scrollIndicatorColor: idleColor,
                scrollIndicatorHoverColor: hoverColor,
                scrollIndicatorActiveColor: activeColor,
                isHitTestVisible: false,
                children: [itemA, itemB, itemC]
            )
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [scrollPanel])
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()

            runtime.pointerMoved(to: Point(x: 79, y: 18))
            _ = runtime.tickAnimations(at: Win32Window.currentTimestampSeconds() + 1)
            XCTAssertEqual(scrollPanel.scrollIndicatorColor, hoverColor)

            runtime.pointerDown(at: Point(x: 79, y: 18))
            _ = runtime.tickAnimations(at: Win32Window.currentTimestampSeconds() + 1)
            XCTAssertEqual(scrollPanel.scrollIndicatorColor, activeColor)

            runtime.pointerMoved(to: Point(x: 79, y: 38))
            XCTAssertGreaterThan(scrollPanel.scrollOffset, 0)

            runtime.pointerUp(at: Point(x: 79, y: 38))
            _ = runtime.tickAnimations(at: Win32Window.currentTimestampSeconds() + 1)
            XCTAssertEqual(scrollPanel.scrollIndicatorColor, hoverColor)

            runtime.pointerExitedWindow()
            _ = runtime.tickAnimations(at: Win32Window.currentTimestampSeconds() + 1)
            XCTAssertEqual(scrollPanel.scrollIndicatorColor, idleColor)
        }
    }

    func testIntrinsicTextSizeSupportsLabelLayout() async {
        await MainActor.run {
            let label = Controls.label("HELLO", color: .white, scale: 2, alignment: .leading)
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 60),
                layoutMode: .stack(.vertical(padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8), alignment: .leading)),
                isHitTestVisible: false,
                children: [label]
            )
            let runtime = RetainedViewRuntime(root: root)

            let rects = drawCommandRects(in: runtime.renderFrame())

            XCTAssertFalse(rects.isEmpty)
            XCTAssertEqual(rects.first?.origin, Point(x: 8, y: 8))
        }
    }

    func testLabelProducesBitmapDrawCommandForNativeTextPath() async {
        await MainActor.run {
            let label = Controls.label("HELLO", color: .white, scale: 2, alignment: .leading)
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 60), isHitTestVisible: false, children: [label])
            let runtime = RetainedViewRuntime(root: root)

            let hasBitmapCommand = runtime.renderFrame().commands.contains { command in
                if case .drawBitmap = command {
                    return true
                }
                return false
            }

            XCTAssertTrue(hasBitmapCommand)
        }
    }

    func testDisplayScaleIncreasesRenderedBitmapResolution() async {
        await MainActor.run {
            let label = Controls.label("HELLO", frame: Rect(x: 10, y: 10, width: 80, height: 24), color: .white, scale: 2, alignment: .leading)
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 60), isHitTestVisible: false, children: [label])
            let runtime = RetainedViewRuntime(root: root, displayScale: 2.0)

            let bitmapCommand = runtime.renderFrame().commands.first { command in
                if case .drawBitmap = command {
                    return true
                }
                return false
            }

            guard case .drawBitmap(let drawBitmap)? = bitmapCommand else {
                return XCTFail("Expected bitmap text command")
            }

            XCTAssertEqual(drawBitmap.bitmap.width, 160)
            XCTAssertEqual(drawBitmap.bitmap.height, 48)
        }
    }

    func testBackgroundGradientFlowsIntoFillRectCommand() async {
        await MainActor.run {
            let gradient = LinearGradient(
                startColor: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                endColor: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                axis: .horizontal
            )
            let node = ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 40), backgroundColor: gradient.startColor, backgroundGradient: gradient)
            let runtime = RetainedViewRuntime(root: node)

            let fills = fillRectCommands(in: runtime.renderFrame())

            XCTAssertEqual(fills.count, 1)
            XCTAssertEqual(fills[0].gradient, .linear(gradient))
        }
    }

    func testOpacityPropagatesIntoRenderFrameCommands() async {
        await MainActor.run {
            let child = ViewNode(
                frame: Rect(x: 10, y: 10, width: 30, height: 20),
                backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.8)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                backgroundColor: Color(red: 0.5, green: 0.6, blue: 0.7, alpha: 0.6),
                opacity: 0.5,
                children: [child]
            )
            let runtime = RetainedViewRuntime(root: root)

            let fills = fillRectCommands(in: runtime.renderFrame())

            XCTAssertEqual(fills.count, 2)
            XCTAssertEqual(fills[0].color.alpha, 0.3, accuracy: 0.001)
            XCTAssertEqual(fills[1].color.alpha, 0.4, accuracy: 0.001)
        }
    }

    func testOpacityPropagatesIntoGradientStops() async {
        await MainActor.run {
            let gradient = LinearGradient(
                startColor: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                endColor: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 0.8),
                axis: .horizontal
            )
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                backgroundColor: gradient.startColor,
                backgroundGradient: gradient,
                opacity: 0.5
            )
            let runtime = RetainedViewRuntime(root: node)

            let fills = fillRectCommands(in: runtime.renderFrame())

            XCTAssertEqual(fills.count, 1)
            XCTAssertEqual(fills[0].color.alpha, 0.5, accuracy: 0.001)
            guard case .linear(let resolvedGradient)? = fills[0].gradient else {
                return XCTFail("Expected linear gradient")
            }
            XCTAssertEqual(resolvedGradient.startColor.alpha, 0.5, accuracy: 0.001)
            XCTAssertEqual(resolvedGradient.endColor.alpha, 0.4, accuracy: 0.001)
        }
    }

    func testZeroOpacityPreservesLayoutButSkipsRenderCommands() async {
        await MainActor.run {
            let child = ViewNode(
                backgroundColor: .white,
                preferredSize: Size(width: 30, height: 20)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                layoutMode: .stack(.vertical(alignment: .leading)),
                opacity: 0,
                children: [child]
            )
            let runtime = RetainedViewRuntime(root: root)

            let frame = runtime.renderFrame()

            XCTAssertTrue(frame.commands.isEmpty)
            XCTAssertEqual(child.resolvedFrame, Rect(x: 0, y: 0, width: 30, height: 20))
        }
    }

    func testSplitViewLaysOutAndDragsDivider() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let splitView = Controls.splitView(
                runtime: runtime,
                axis: .horizontal,
                frame: Rect(x: 0, y: 0, width: 200, height: 100),
                ratio: 0.3,
                minPrimaryExtent: 40,
                minSecondaryExtent: 40,
                dividerThickness: 20,
                primary: [Controls.panel(backgroundColor: .white)],
                secondary: [Controls.panel(backgroundColor: .black)]
            )

            runtime.root.addChild(splitView)
            _ = runtime.renderFrame()

            let initialPrimaryWidth = splitView.children[0].frame.size.width
            XCTAssertEqual(initialPrimaryWidth, 54)

            runtime.pointerDown(at: Point(x: 60, y: 40))
            runtime.pointerMoved(to: Point(x: 100, y: 40))
            runtime.pointerUp(at: Point(x: 100, y: 40))

            XCTAssertGreaterThan(splitView.children[0].frame.size.width, initialPrimaryWidth)
            XCTAssertLessThan(splitView.children[1].frame.size.width, 126)
        }
    }

    func testKeyboardScrollKeysAffectScrollableAncestorOfFocusedNode() async {
        await MainActor.run {
            let child = ViewNode(frame: Rect(x: 0, y: 0, width: 60, height: 40), isFocusable: true)
            let filler = ViewNode(frame: Rect(x: 0, y: 90, width: 60, height: 40), isFocusable: true)
            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 70),
                layoutMode: .absolute,
                scrollAxis: .vertical,
                scrollStep: 20,
                isHitTestVisible: false,
                children: [child, filler]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                isHitTestVisible: false,
                children: [scrollPanel]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.pointerDown(at: Point(x: 20, y: 20))
            runtime.pointerUp(at: Point(x: 20, y: 20))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.pageDown.rawValue))
            XCTAssertEqual(scrollPanel.scrollOffset, 59.5)

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.home.rawValue))
            XCTAssertEqual(scrollPanel.scrollOffset, 0)

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.end.rawValue))
            XCTAssertEqual(scrollPanel.scrollOffset, 60)
        }
    }

    func testNodeDragCallbacksReceivePointerDelta() async {
        await MainActor.run {
            var startPoints: [Point] = []
            var dragDeltas: [Point] = []
            var endDeltas: [Point] = []

            let handle = ViewNode(frame: Rect(x: 10, y: 10, width: 24, height: 24))
            handle.onDragStart = { point in startPoints.append(point) }
            handle.onDragChange = { _, delta in dragDeltas.append(delta) }
            handle.onDragEnd = { _, delta in endDeltas.append(delta) }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                isHitTestVisible: false,
                children: [handle]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.pointerDown(at: Point(x: 14, y: 16))
            runtime.pointerMoved(to: Point(x: 28, y: 42))
            runtime.pointerUp(at: Point(x: 28, y: 42))

            XCTAssertEqual(startPoints, [Point(x: 14, y: 16)])
            XCTAssertEqual(dragDeltas.last, Point(x: 14, y: 26))
            XCTAssertEqual(endDeltas, [Point(x: 14, y: 26)])
        }
    }
}

private func fillRectCommands(in frame: RenderFrame) -> [FillRectCommand] {
    frame.commands.compactMap { command in
        guard case .fillRect(let fillRect) = command else {
            return nil
        }

        return fillRect
    }
}

private func drawCommandRects(in frame: RenderFrame) -> [Rect] {
    frame.commands.compactMap { command in
        switch command {
        case .fillRect(let fillRect):
            return fillRect.rect
        case .drawBitmap(let drawBitmap):
            return drawBitmap.rect
        case .applyBlur(let blur):
            return blur.region
        case .fillPath, .strokePath, .drawText, .pushClip, .popClip:
            return nil
        }
    }
}
