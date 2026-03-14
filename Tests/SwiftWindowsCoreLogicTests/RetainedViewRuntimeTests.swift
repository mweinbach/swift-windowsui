import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
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
}

private func fillRectCommands(in frame: RenderFrame) -> [FillRectCommand] {
    frame.commands.compactMap { command in
        guard case .fillRect(let fillRect) = command else {
            return nil
        }

        return fillRect
    }
}
