import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsLayout

import SwiftWindowsPlatform

import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RuntimeTestClock {
    var now: Double = 0
}

// MARK: - VAL-PARITY-001: Normalized Output Comparison Helpers

/// Helper struct for normalized output comparison (VAL-PARITY-001)

final class RetainedViewRuntimeTests: XCTestCase {
    func testUnmountLifecycleFiresForRemovedAndReplacedSubtrees() async {
        await MainActor.run {
            var events: [String] = []

            let child = ViewNode(
                frame: Rect(x: 4, y: 4, width: 10, height: 10),
                backgroundColor: .white
            )
            child.onDisappear = {
                events.append("child")
            }
            let parent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 20, height: 20),
                backgroundColor: .white,
                children: [child]
            )
            parent.onDisappear = {
                events.append("parent")
            }
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                children: [parent]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()
            root.replaceChild(at: 0, with: ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10)))

            XCTAssertEqual(events, ["parent", "child"])

            events.removeAll()
            let removedChild = ViewNode(
                frame: Rect(x: 6, y: 6, width: 10, height: 10),
                backgroundColor: .white
            )
            removedChild.onDisappear = {
                events.append("removedChild")
            }
            let removedParent = ViewNode(
                frame: Rect(x: 30, y: 0, width: 20, height: 20),
                backgroundColor: .white,
                children: [removedChild]
            )
            removedParent.onDisappear = {
                events.append("removedParent")
            }

            root.addChild(removedParent)
            _ = runtime.renderFrame()
            root.removeChild(at: 1)

            XCTAssertEqual(events, ["removedParent", "removedChild"])
        }
    }

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

    func testStackLayoutUsesRetainedAlignmentGuidesOnCrossAxis() async {
        await MainActor.run {
            let verticalGuided = ViewNode(
                preferredSize: Size(width: 20, height: 10),
                alignmentGuides: [
                    RetainedAlignmentGuide(axis: .horizontal, guide: "center", value: 5)
                ]
            )
            let verticalDefault = ViewNode(preferredSize: Size(width: 20, height: 10))
            let verticalRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 60),
                layoutMode: .stack(.vertical(alignment: .center)),
                children: [verticalGuided, verticalDefault]
            )

            let horizontalGuided = ViewNode(
                preferredSize: Size(width: 10, height: 20),
                alignmentGuides: [
                    RetainedAlignmentGuide(axis: .vertical, guide: "center", value: 5)
                ]
            )
            let horizontalDefault = ViewNode(preferredSize: Size(width: 10, height: 20))
            let horizontalRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 60),
                layoutMode: .stack(.horizontal(alignment: .center)),
                children: [horizontalGuided, horizontalDefault]
            )
            let baselineShort = ViewNode(preferredSize: Size(width: 10, height: 20))
            let baselineTall = ViewNode(preferredSize: Size(width: 10, height: 40))
            let baselineRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 60),
                layoutMode: .stack(.horizontal(alignment: .firstTextBaseline)),
                children: [baselineShort, baselineTall]
            )
            let customHorizontalGuided = ViewNode(
                preferredSize: Size(width: 20, height: 10),
                alignmentGuides: [
                    RetainedAlignmentGuide(axis: .horizontal, guide: "custom:test", value: 7)
                ]
            )
            let customHorizontalRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 60),
                layoutMode: .stack(.vertical(alignment: .customHorizontal("custom:test"))),
                children: [customHorizontalGuided]
            )
            let customVerticalGuided = ViewNode(
                preferredSize: Size(width: 10, height: 20),
                alignmentGuides: [
                    RetainedAlignmentGuide(axis: .vertical, guide: "custom:test", value: 9)
                ]
            )
            let customVerticalRoot = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 60),
                layoutMode: .stack(.horizontal(alignment: .customVertical("custom:test"))),
                children: [customVerticalGuided]
            )

            _ = RetainedViewRuntime(root: verticalRoot).renderFrame()
            _ = RetainedViewRuntime(root: horizontalRoot).renderFrame()
            _ = RetainedViewRuntime(root: baselineRoot).renderFrame()
            _ = RetainedViewRuntime(root: customHorizontalRoot).renderFrame()
            _ = RetainedViewRuntime(root: customVerticalRoot).renderFrame()

            XCTAssertEqual(verticalGuided.resolvedFrame, Rect(x: 45, y: 0, width: 20, height: 10))
            XCTAssertEqual(verticalDefault.resolvedFrame, Rect(x: 40, y: 10, width: 20, height: 10))
            XCTAssertEqual(horizontalGuided.resolvedFrame, Rect(x: 0, y: 25, width: 10, height: 20))
            XCTAssertEqual(horizontalDefault.resolvedFrame, Rect(x: 10, y: 20, width: 10, height: 20))
            XCTAssertEqual(baselineShort.resolvedFrame, Rect(x: 0, y: 32, width: 10, height: 20))
            XCTAssertEqual(baselineTall.resolvedFrame, Rect(x: 10, y: 16, width: 10, height: 40))
            XCTAssertEqual(customHorizontalGuided.resolvedFrame, Rect(x: -7, y: 0, width: 20, height: 10))
            XCTAssertEqual(customVerticalGuided.resolvedFrame, Rect(x: 0, y: -9, width: 10, height: 20))
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

    func testDashedSquareBorderEmitsSegmentedFillCommands() async {
        await MainActor.run {
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 20, height: 10),
                backgroundColor: .white,
                borderColor: .black,
                borderWidth: 2,
                borderStrokeStyle: StrokeStyle(lineWidth: 2, dashPattern: [4, 2])
            )
            let runtime = RetainedViewRuntime(root: root)

            let fills = fillRectCommands(in: runtime.renderFrame())

            XCTAssertGreaterThan(fills.count, 2)
            XCTAssertEqual(fills.first?.rect, Rect(x: 0, y: 0, width: 4, height: 2))
            XCTAssertFalse(fills.contains { $0.rect == Rect(x: 0, y: 0, width: 20, height: 10) })
            XCTAssertEqual(fills.last?.rect, Rect(x: 2, y: 2, width: 16, height: 6))
        }
    }

    func testDashedSquareBorderMapsRoundLineCapsToSegmentCornerRadius() async {
        await MainActor.run {
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 20, height: 10),
                backgroundColor: .white,
                borderColor: .black,
                borderWidth: 2,
                borderStrokeStyle: StrokeStyle(lineWidth: 2, dashPattern: [4, 2], lineCap: .round)
            )
            let runtime = RetainedViewRuntime(root: root)

            let firstFill = fillRectCommands(in: runtime.renderFrame()).first

            XCTAssertEqual(firstFill?.rect, Rect(x: 0, y: 0, width: 5, height: 2))
            XCTAssertEqual(firstFill?.cornerRadius, 1)
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
            var insideLocations: [Point] = []
            var outsideCount = 0
            var activationCount = 0

            let target = ViewNode(frame: Rect(x: 10, y: 10, width: 20, height: 20))
            target.onPointerDown = { pointerDownCount += 1 }
            target.onPointerUpInside = { insideCount += 1 }
            target.onPointerUpInsideAt = { insideLocations.append($0) }
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
            XCTAssertEqual(insideLocations, [Point(x: 16, y: 16)])
            XCTAssertEqual(outsideCount, 1)
            XCTAssertEqual(activationCount, 1)
        }
    }

    func testEnabledButtonRepeatInvokesActionDuringProlongedPress() async {
        await MainActor.run {
            var activationCount = 0
            let palette = SurfacePalette(
                idle: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                focused: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                pressed: Color(red: 0.5, green: 0.6, blue: 0.7, alpha: 1)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 50),
                isHitTestVisible: false
            )
            let runtime = RetainedViewRuntime(root: root)
            let button = Controls.button(
                runtime: runtime,
                frame: Rect(x: 10, y: 8, width: 40, height: 24),
                cornerRadius: 4,
                palette: palette,
                chrome: SurfaceChrome(),
                repeatBehavior: .enabled,
                animation: ControlAnimationStyle(focusDuration: 0, pressDuration: 0),
                action: {
                    activationCount += 1
                }
            )
            root.addChild(button)

            runtime.pointerDown(at: Point(x: 20, y: 16))

            XCTAssertTrue(runtime.hasActiveAnimations)
            XCTAssertFalse(runtime.tickAnimations(at: 1.0))
            XCTAssertEqual(activationCount, 0)
            XCTAssertFalse(runtime.tickAnimations(at: 1.44))
            XCTAssertEqual(activationCount, 0)
            XCTAssertTrue(runtime.tickAnimations(at: 1.45))
            XCTAssertEqual(activationCount, 1)
            XCTAssertTrue(runtime.tickAnimations(at: 1.531))
            XCTAssertEqual(activationCount, 2)

            runtime.pointerUp(at: Point(x: 20, y: 16))

            XCTAssertEqual(activationCount, 2)
            // The release also starts the button's scale-back animation, which
            // legitimately keeps the animation driver running — per-node
            // `animationStates` is part of `hasActiveAnimations` now. What has
            // to be finished is the repeat state: no further tick activates.
            XCTAssertFalse(runtime.tickAnimations(at: 2.0))
            XCTAssertEqual(activationCount, 2)
        }
    }

    func testEnabledButtonRepeatKeepsReleaseActivationBeforeDelay() async {
        await MainActor.run {
            var activationCount = 0
            let palette = SurfacePalette(
                idle: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                focused: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                pressed: Color(red: 0.5, green: 0.6, blue: 0.7, alpha: 1)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 50),
                isHitTestVisible: false
            )
            let runtime = RetainedViewRuntime(root: root)
            let button = Controls.button(
                runtime: runtime,
                frame: Rect(x: 10, y: 8, width: 40, height: 24),
                cornerRadius: 4,
                palette: palette,
                chrome: SurfaceChrome(),
                repeatBehavior: .enabled,
                animation: ControlAnimationStyle(focusDuration: 0, pressDuration: 0),
                action: {
                    activationCount += 1
                }
            )
            root.addChild(button)

            runtime.pointerDown(at: Point(x: 20, y: 16))
            XCTAssertFalse(runtime.tickAnimations(at: 1.0))
            XCTAssertFalse(runtime.tickAnimations(at: 1.2))
            runtime.pointerUp(at: Point(x: 20, y: 16))

            XCTAssertEqual(activationCount, 1)
            // See above: the release scale animation keeps the driver on; the
            // repeat state is what must be finished.
            XCTAssertFalse(runtime.tickAnimations(at: 2.0))
            XCTAssertEqual(activationCount, 1)
        }
    }

    func testDisabledButtonRepeatKeepsSingleReleaseActivation() async {
        await MainActor.run {
            var activationCount = 0
            let palette = SurfacePalette(
                idle: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                focused: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                pressed: Color(red: 0.5, green: 0.6, blue: 0.7, alpha: 1)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 50),
                isHitTestVisible: false
            )
            let runtime = RetainedViewRuntime(root: root)
            let button = Controls.button(
                runtime: runtime,
                frame: Rect(x: 10, y: 8, width: 40, height: 24),
                cornerRadius: 4,
                palette: palette,
                chrome: SurfaceChrome(),
                repeatBehavior: .disabled,
                animation: ControlAnimationStyle(focusDuration: 0, pressDuration: 0),
                action: {
                    activationCount += 1
                }
            )
            root.addChild(button)

            runtime.pointerDown(at: Point(x: 20, y: 16))
            XCTAssertFalse(runtime.tickAnimations(at: 1.0))
            XCTAssertFalse(runtime.tickAnimations(at: 1.6))
            XCTAssertEqual(activationCount, 0)

            runtime.pointerUp(at: Point(x: 20, y: 16))

            XCTAssertEqual(activationCount, 1)
            // See above: the release scale animation keeps the driver on; the
            // repeat state is what must be finished.
            XCTAssertFalse(runtime.tickAnimations(at: 2.0))
            XCTAssertEqual(activationCount, 1)
        }
    }

    func testRenderFrameCapturesButtonVisualStateChanges() async {
        await MainActor.run {
            let palette = SurfacePalette(
                idle: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                focused: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                pressed: Color(red: 0.5, green: 0.6, blue: 0.7, alpha: 1)
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
                animation: ControlAnimationStyle(focusDuration: 0, pressDuration: 0)
            )
            button.isFocusEffectDisabled = true
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

            // Activating a control does not repaint it. There is no third
            // colour past `pressed`: AppKit releases the highlight on mouseUp
            // and *then* sends the action, so a keyboard activation leaves the
            // button exactly where it was — focused, because it still is.
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
        }
    }

    func testHoverEffectHighlightRendersOnFramePath() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                backgroundColor: .black,
                hoverEffect: .highlight
            )
            let runtime = RetainedViewRuntime(root: node)

            runtime.pointerMoved(to: Point(x: 20, y: 20))
            let hoveredFrame = runtime.renderFrame()
            runtime.pointerExitedWindow()
            let unhoveredFrame = runtime.renderFrame()

            XCTAssertFalse(node.isHovered)
            XCTAssertTrue(
                fillRectCommands(in: hoveredFrame).contains {
                    $0.color == Color(red: 1, green: 1, blue: 1, alpha: 0.10)
                }
            )
            XCTAssertFalse(
                fillRectCommands(in: unhoveredFrame).contains {
                    $0.color == Color(red: 1, green: 1, blue: 1, alpha: 0.10)
                }
            )
        }
    }

    func testPointerMovedCallsMoveHandlerForHitNode() async {
        await MainActor.run {
            var moveLocations: [Point] = []
            let target = ViewNode(
                frame: Rect(x: 10, y: 10, width: 40, height: 30),
                isHitTestVisible: true
            )
            target.onPointerMove = { moveLocations.append($0) }
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isHitTestVisible: false,
                children: [target]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.pointerMoved(to: Point(x: 12, y: 14))
            runtime.pointerMoved(to: Point(x: 20, y: 24))
            runtime.pointerMoved(to: Point(x: 90, y: 90))

            XCTAssertEqual(moveLocations, [Point(x: 12, y: 14), Point(x: 20, y: 24)])
        }
    }

    func testHoverEffectHighlightRendersOnScenePath() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                backgroundColor: .black,
                hoverEffect: .highlight
            )
            let runtime = RetainedViewRuntime(root: node)

            runtime.pointerMoved(to: Point(x: 20, y: 20))
            let scene = runtime.renderScene()

            XCTAssertTrue(sceneQuadColors(in: scene).contains(Color(red: 1, green: 1, blue: 1, alpha: 0.10)))
        }
    }

    func testHoverEffectUsesHoverContentShapeForVisualRadius() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                backgroundColor: .black,
                cornerRadius: 4,
                hoverEffect: .highlight,
                contentShapes: [
                    RetainedContentShape(kinds: .hoverEffect, style: .capsule)
                ]
            )
            let runtime = RetainedViewRuntime(root: node)

            runtime.pointerMoved(to: Point(x: 20, y: 20))
            let frame = runtime.renderFrame()
            let scene = runtime.renderScene()

            let hoverColor = Color(red: 1, green: 1, blue: 1, alpha: 0.10)
            XCTAssertTrue(
                fillRectCommands(in: frame).contains {
                    $0.color == hoverColor && $0.cornerRadius == 20
                }
            )
            XCTAssertTrue(
                scene.layers.flatMap(\.quads).contains {
                    Color(red: $0.startR, green: $0.startG, blue: $0.startB, alpha: $0.startA) == hoverColor
                        && $0.cornerRadius == 20
                }
            )
        }
    }

    func testHoverEffectLiftRendersShadowAndOverlay() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                backgroundColor: .black,
                hoverEffect: .lift
            )
            let runtime = RetainedViewRuntime(root: node)

            runtime.pointerMoved(to: Point(x: 20, y: 20))
            let frame = runtime.renderFrame()
            let scene = runtime.renderScene()

            XCTAssertTrue(
                fillRectCommands(in: frame).contains {
                    $0.color == Color(red: 0, green: 0, blue: 0, alpha: 0.18)
                }
            )
            XCTAssertTrue(
                fillRectCommands(in: frame).contains {
                    $0.color == Color(red: 1, green: 1, blue: 1, alpha: 0.07)
                }
            )
            XCTAssertTrue(sceneQuadColors(in: scene).contains(Color(red: 0, green: 0, blue: 0, alpha: 0.18)))
            XCTAssertTrue(sceneQuadColors(in: scene).contains(Color(red: 1, green: 1, blue: 1, alpha: 0.07)))
        }
    }

    func testFocusedNodeRendersFocusEffectOnFrameAndScenePaths() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 4, y: 4, width: 80, height: 40),
                backgroundColor: .black,
                isFocusable: true
            )
            let runtime = RetainedViewRuntime(root: node)

            runtime.pointerDown(at: Point(x: 20, y: 20))
            let frame = runtime.renderFrame()
            let scene = runtime.renderScene()

            let focusColor = Color(red: 0.25, green: 0.55, blue: 1, alpha: 0.75)
            XCTAssertTrue(node.isFocused)
            XCTAssertTrue(fillRectCommands(in: frame).contains { $0.color == focusColor })
            XCTAssertTrue(sceneQuadColors(in: scene).contains(focusColor))
        }
    }

    func testFocusEffectUsesFocusContentShapeForVisualRadius() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 4, y: 4, width: 80, height: 40),
                backgroundColor: .black,
                cornerRadius: 4,
                isFocusable: true,
                contentShapes: [
                    RetainedContentShape(kinds: .focusEffect, style: .roundedRectangle(12))
                ]
            )
            let runtime = RetainedViewRuntime(root: node)

            runtime.pointerDown(at: Point(x: 20, y: 20))
            let frame = runtime.renderFrame()
            let scene = runtime.renderScene()

            let focusColor = Color(red: 0.25, green: 0.55, blue: 1, alpha: 0.75)

            // The halo is a ring, so its radius is no longer readable off a
            // single quad — it is visible in the ring's geometry. The ring
            // frame is the 80pt-wide node outset by the 2pt halo, so 84pt; its
            // straight top edge spans that minus a corner radius at each end.
            // With the `.focusEffect` content shape's 12pt radius (+2 for the
            // halo) that is 84 - 28 = 56. Falling back to the node's own 4pt
            // radius would give 84 - 12 = 72, so the two are distinguishable.
            let expectedTopEdgeWidth = 84.0 - 2 * 14

            let framedEdges = fillRectCommands(in: frame).filter { $0.color == focusColor }
            XCTAssertFalse(framedEdges.isEmpty, "the halo is still drawn on the frame path")
            XCTAssertEqual(
                framedEdges.map(\.rect.size.width).max() ?? 0, expectedTopEdgeWidth, accuracy: 1e-6,
                "the frame path's halo follows the focusEffect content shape's radius")

            let sceneEdges = scene.layers.flatMap(\.quads).filter {
                Color(red: $0.startR, green: $0.startG, blue: $0.startB, alpha: $0.startA) == focusColor
            }
            XCTAssertFalse(sceneEdges.isEmpty, "the halo is still drawn on the scene path")
            XCTAssertEqual(
                Double(sceneEdges.map(\.width).max() ?? 0), expectedTopEdgeWidth, accuracy: 1e-4,
                "and the scene path agrees with it")
        }
    }

    func testFocusEffectDisabledSuppressesFocusRing() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 4, y: 4, width: 80, height: 40),
                backgroundColor: .black,
                isFocusable: true,
                isFocusEffectDisabled: true
            )
            let runtime = RetainedViewRuntime(root: node)

            runtime.pointerDown(at: Point(x: 20, y: 20))
            let frame = runtime.renderFrame()

            XCTAssertTrue(node.isFocused)
            XCTAssertFalse(
                fillRectCommands(in: frame).contains {
                    $0.color == Color(red: 0.25, green: 0.55, blue: 1, alpha: 0.75)
                }
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

    @MainActor
    private static func makeScrollMotionRuntime(
        contentHeight: Double = 1_200, offset: Double = 0
    ) -> (RetainedViewRuntime, ViewNode, RuntimeTestClock) {
        let marker = ViewNode(
            frame: Rect(x: 0, y: 20, width: 40, height: 8), backgroundColor: .white)
        let content = ViewNode(
            frame: Rect(x: 0, y: 0, width: 80, height: contentHeight), children: [marker])
        let scroller = ViewNode(
            frame: Rect(x: 10, y: 10, width: 80, height: 80),
            clipsToBounds: true,
            scrollAxis: .vertical,
            scrollOffset: offset,
            scrollStep: 20,
            children: [content])
        let runtime = RetainedViewRuntime(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isHitTestVisible: false, children: [scroller]))
        let clock = RuntimeTestClock()
        runtime.clock = { clock.now }
        _ = runtime.renderScene()
        return (runtime, scroller, clock)
    }

    func testKeyboardScrollMovesEveryRenderedFrameAndReachesItsTarget() async {
        await MainActor.run {
            let (runtime, scroller, clock) = Self.makeScrollMotionRuntime()
            runtime.pointerMoved(to: Point(x: 30, y: 30))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            _ = runtime.renderScene()
            XCTAssertEqual(scroller.resolvedScrollOffset, 0, accuracy: 0.0001)

            for time in [0.055, 0.11, 0.22] {
                clock.now = time
                XCTAssertTrue(runtime.tickAnimations(at: time))
                let scene = runtime.renderScene()
                let expectedOffset = scroller.scrollOffset + scroller.scrollPresentedDelta
                XCTAssertEqual(scroller.resolvedScrollOffset, expectedOffset, accuracy: 0.0001)
                guard let marker = scene.layers.flatMap(\.quads).first else {
                    return XCTFail("the moving marker must remain visible")
                }
                XCTAssertEqual(Double(marker.y), 30 - expectedOffset, accuracy: 0.001)
            }
            XCTAssertEqual(scroller.resolvedScrollOffset, 20, accuracy: 0.0001)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testRubberBandUpdatesRenderedGeometryUntilItReturnsToRest() async {
        await MainActor.run {
            let (runtime, scroller, clock) = Self.makeScrollMotionRuntime()
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: 3)
            let peak = scroller.scrollOvershoot
            XCTAssertLessThan(peak, 0)

            for time in [0.0, 0.05, 0.1, 1.0] {
                clock.now = time
                _ = runtime.tickAnimations(at: time)
                let scene = runtime.renderScene()
                XCTAssertEqual(scroller.resolvedScrollOffset, scroller.scrollOvershoot, accuracy: 0.0001)
                guard let marker = scene.layers.flatMap(\.quads).first else {
                    return XCTFail("the bouncing marker must remain visible")
                }
                XCTAssertEqual(Double(marker.y), 30 - scroller.scrollOvershoot, accuracy: 0.001)
            }
            XCTAssertEqual(scroller.resolvedScrollOffset, 0, accuracy: 0.0001)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testWheelInterruptsKeyboardScrollAtThePresentedPosition() async {
        await MainActor.run {
            let (runtime, scroller, clock) = Self.makeScrollMotionRuntime()
            runtime.pointerMoved(to: Point(x: 30, y: 30))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.pageDown.rawValue))
            clock.now = 0.055
            _ = runtime.tickAnimations(at: clock.now)
            _ = runtime.renderScene()
            let presentedOffset = scroller.resolvedScrollOffset

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1)
            XCTAssertEqual(scroller.scrollOffset, presentedOffset + 20, accuracy: 0.0001)
            XCTAssertEqual(scroller.scrollPresentedDelta, 0)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testWheelNotchCancelsAnOpposingPreciseMomentumTail() async {
        await MainActor.run {
            let (runtime, scroller, clock) = Self.makeScrollMotionRuntime()
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3, source: .precise)
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: 1)
            XCTAssertEqual(scroller.scrollOffset, 40, accuracy: 0.0001)
            clock.now = 0.5
            _ = runtime.tickAnimations(at: clock.now)
            XCTAssertEqual(scroller.scrollOffset, 40, accuracy: 0.0001)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testPreciseScrollDistanceIsIndependentOfFrameRate() async {
        await MainActor.run {
            for framesPerSecond in [20, 30, 60, 120] {
                let (runtime, scroller, clock) = Self.makeScrollMotionRuntime()
                runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3, source: .precise)
                for frame in 1...(framesPerSecond / 2) {
                    clock.now = Double(frame) / Double(framesPerSecond)
                    _ = runtime.tickAnimations(at: clock.now)
                    let offset = scroller.scrollOffset
                    for staleTime in [clock.now, clock.now - 0.5 / Double(framesPerSecond), .nan, .infinity] {
                        XCTAssertFalse(runtime.tickAnimations(at: staleTime))
                        XCTAssertEqual(scroller.scrollOffset, offset, accuracy: 0.0001)
                    }
                }
                XCTAssertEqual(scroller.scrollOffset, 60 + 50 * (1 - exp(-3)), accuracy: 0.0001)
                clock.now = 1
                _ = runtime.tickAnimations(at: clock.now)
                XCTAssertEqual(scroller.scrollOffset, 109, accuracy: 0.0001)
                XCTAssertFalse(runtime.hasActiveAnimations)
            }
        }
    }

    func testRubberBandReturnIsIndependentOfFrameRate() async {
        await MainActor.run {
            for framesPerSecond in [20, 30, 60, 120] {
                let (runtime, scroller, clock) = Self.makeScrollMotionRuntime()
                runtime.mouseWheel(at: Point(x: 30, y: 30), delta: 3)
                let initialOvershoot = scroller.scrollOvershoot
                for frame in 1...(framesPerSecond / 10) {
                    clock.now = Double(frame) / Double(framesPerSecond)
                    _ = runtime.tickAnimations(at: clock.now)
                }
                let expected = initialOvershoot * (5 * exp(-1.2) - 4 * exp(-1.5))
                XCTAssertEqual(scroller.scrollOvershoot, expected, accuracy: 0.0001)
            }
        }
    }

    func testContinuousPreciseInputDecaysPreviousImpulsesBeforeAddingNewOnes() async {
        await MainActor.run {
            let (runtime, scroller, clock) = Self.makeScrollMotionRuntime(contentHeight: 10_000)
            for frame in 1...60 {
                clock.now = Double(frame) / 60
                runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -1, source: .precise)
                _ = runtime.tickAnimations(at: clock.now)
            }
            let offsetAtRelease = scroller.scrollOffset
            clock.now = 3
            _ = runtime.tickAnimations(at: clock.now)
            let velocityAtRelease = 100 * (1 - exp(-6)) / (1 - exp(-0.1))
            XCTAssertEqual(scroller.scrollOffset - offsetAtRelease, (velocityAtRelease - 6) / 6, accuracy: 0.0001)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testFastGlideKeepsTheSameCappedBounceAtEveryFrameRate() async {
        await MainActor.run {
            for framesPerSecond in [20, 30, 60, 120] {
                let (runtime, scroller, clock) = Self.makeScrollMotionRuntime(contentHeight: 12_000, offset: 11_100)
                runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -40, source: .precise)
                for frame in 1...(framesPerSecond / 5) {
                    clock.now = Double(frame) / Double(framesPerSecond)
                    _ = runtime.tickAnimations(at: clock.now)
                    if frame == framesPerSecond / 10 {
                        XCTAssertEqual(scroller.scrollOvershoot, 80, accuracy: 0.0001)
                    }
                }
                let springTime = 0.2 + log(0.97) / 6
                let expected = (3_880.0 / 3) * (exp(-12 * springTime) - exp(-15 * springTime))
                XCTAssertEqual(scroller.scrollOffset, 11_920, accuracy: 0.0001)
                XCTAssertEqual(scroller.scrollOvershoot, expected, accuracy: 0.0001)
            }
        }
    }

    func testLongFrameGapSettlesMomentumIncludingAnEdgeCollision() async {
        await MainActor.run {
            let (runtime, scroller, clock) = Self.makeScrollMotionRuntime(offset: 1_060)
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -2, source: .precise)
            clock.now = 5
            _ = runtime.tickAnimations(at: clock.now)
            XCTAssertEqual(scroller.scrollOffset, 1_120, accuracy: 0.0001)
            XCTAssertEqual(scroller.scrollOvershoot, 0, accuracy: 0.0001)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testNestedScrollerPassesUnusedWheelLinesToItsAncestor() async {
        await MainActor.run {
            let (runtime, outer, _) = Self.makeScrollMotionRuntime()
            let inner = ViewNode(
                frame: Rect(x: 0, y: 10, width: 70, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 40,
                scrollStep: 10,
                children: [ViewNode(frame: Rect(x: 0, y: 0, width: 70, height: 100))])
            outer.children[0].addChild(inner)
            _ = runtime.renderScene()

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3)
            XCTAssertEqual(inner.scrollOffset, 50, accuracy: 0.0001)
            XCTAssertEqual(outer.scrollOffset, 40, accuracy: 0.0001)
            XCTAssertEqual(inner.scrollOvershoot, 0)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testNestedScrollerWithFittingContentDoesNotSwallowWheelInput() async {
        await MainActor.run {
            let (runtime, outer, _) = Self.makeScrollMotionRuntime()
            let inner = ViewNode(
                frame: Rect(x: 0, y: 10, width: 70, height: 50),
                scrollAxis: .vertical,
                children: [ViewNode(frame: Rect(x: 0, y: 0, width: 70, height: 30))])
            outer.children[0].addChild(inner)
            _ = runtime.renderScene()

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3)
            XCTAssertEqual(inner.scrollOffset, 0)
            XCTAssertEqual(outer.scrollOffset, 60, accuracy: 0.0001)
        }
    }

    func testNestedWheelChainingDoesNotEscapeAModalPresentation() async {
        await MainActor.run {
            let (runtime, outer, _) = Self.makeScrollMotionRuntime()
            let modal = ViewNode(
                frame: Rect(x: 0, y: 10, width: 70, height: 50),
                scrollAxis: .vertical,
                accessibilityTraits: [.isModal],
                children: [ViewNode(frame: Rect(x: 0, y: 0, width: 70, height: 30))])
            outer.children[0].addChild(modal)
            _ = runtime.renderScene()

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3)
            XCTAssertEqual(modal.scrollOffset, 0)
            XCTAssertEqual(outer.scrollOffset, 0)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testFittingScrollAncestorDoesNotSuppressInnerEdgeFeedback() async {
        await MainActor.run {
            let (runtime, outer, _) = Self.makeScrollMotionRuntime(contentHeight: 80)
            let inner = ViewNode(
                frame: Rect(x: 0, y: 10, width: 70, height: 50),
                scrollAxis: .vertical,
                children: [ViewNode(frame: Rect(x: 0, y: 0, width: 70, height: 100))])
            outer.children[0].addChild(inner)
            _ = runtime.renderScene()

            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: 3)
            XCTAssertEqual(outer.scrollOffset, 0)
            XCTAssertEqual(outer.scrollOvershoot, 0)
            XCTAssertLessThan(inner.scrollOvershoot, 0)
            XCTAssertTrue(runtime.hasActiveAnimations)
        }
    }

    func testScrollMotionStopsWhenItsNodeLeavesTheRuntimeOrBecomesHidden() async {
        await MainActor.run {
            for detach in [true, false] {
                let (runtime, scroller, clock) = Self.makeScrollMotionRuntime()
                runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3, source: .precise)
                let offset = scroller.scrollOffset
                if detach {
                    runtime.root.removeChild(scroller)
                } else {
                    scroller.isHidden = true
                }
                clock.now = 0.5
                _ = runtime.tickAnimations(at: clock.now)
                XCTAssertEqual(scroller.scrollOffset, offset, accuracy: 0.0001)
                XCTAssertFalse(runtime.hasActiveAnimations)
            }
        }
    }

    func testDisablingScrollClearsAnActiveRubberBand() async {
        await MainActor.run {
            let (runtime, scroller, clock) = Self.makeScrollMotionRuntime()
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: 3)
            XCTAssertNotEqual(scroller.scrollOvershoot, 0)
            scroller.scrollAxis = nil
            clock.now = 0.1
            _ = runtime.tickAnimations(at: clock.now)
            XCTAssertEqual(scroller.scrollOvershoot, 0)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testInvalidWheelDeltasDoNotResetTheViewportOrStartMotion() async {
        await MainActor.run {
            let (runtime, scroller, _) = Self.makeScrollMotionRuntime(offset: 100)
            for delta in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, 0] {
                runtime.mouseWheel(at: Point(x: 30, y: 30), delta: delta, source: .precise)
                XCTAssertEqual(scroller.scrollOffset, 100, accuracy: 0.0001)
                XCTAssertFalse(runtime.hasActiveAnimations)
            }
        }
    }

    func testMouseWheelScrollsNearestScrollableAncestorAndClampsOffset() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 30))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 30))
            let itemC = ViewNode(
                backgroundColor: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                preferredSize: Size(width: 60, height: 30))

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 70),
                layoutMode: .stack(
                    .vertical(spacing: 10, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))),
                scrollAxis: .vertical,
                scrollStep: 20,
                showsScrollIndicator: true,
                isHitTestVisible: false,
                children: [itemA, itemB, itemC]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [scrollPanel])
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

    func testMouseWheelSeedsScrollMomentumThatDecaysToStop() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 200))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 200))
            let itemC = ViewNode(
                backgroundColor: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                preferredSize: Size(width: 60, height: 200))

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 80),
                layoutMode: .stack(
                    .vertical(spacing: 10, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))),
                scrollAxis: .vertical,
                scrollStep: 20,
                isHitTestVisible: false,
                children: [itemA, itemB, itemC]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [scrollPanel])
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()
            XCTAssertFalse(runtime.hasActiveAnimations)

            // Precision-device impulse: immediate jump + seeded momentum.
            // A click-wheel detent gets no momentum at all — AppKit gives a
            // momentum phase only to gesture devices — so the source has to be
            // stated for this to be the scroll it is testing.
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3, source: .precise)
            let offsetAfterWheel = scrollPanel.scrollOffset
            XCTAssertEqual(offsetAfterWheel, 60)
            XCTAssertTrue(runtime.hasActiveAnimations, "Wheel impulse should seed momentum")

            // The first tick after seeding glides only by the time actually
            // elapsed since the wheel — microseconds on a monotonic frame
            // clock, where the old tick-count clock quantized it to exactly
            // zero.
            let t0 = Win32Window.currentTimestampSeconds()
            _ = runtime.tickAnimations(at: t0)
            XCTAssertEqual(scrollPanel.scrollOffset, offsetAfterWheel, accuracy: 0.1)

            // Subsequent ticks glide further in the direction of the wheel.
            _ = runtime.tickAnimations(at: t0 + 0.016)
            let offsetMid = scrollPanel.scrollOffset
            XCTAssertGreaterThan(offsetMid, offsetAfterWheel, "Momentum should keep advancing offset")

            // After enough simulated frames, momentum decays below threshold and stops.
            var tickTime = t0 + 0.016
            var ticks = 0
            while runtime.hasActiveAnimations, ticks < 240 {
                tickTime += 0.016
                _ = runtime.tickAnimations(at: tickTime)
                ticks += 1
            }
            XCTAssertFalse(runtime.hasActiveAnimations, "Momentum should decay to a stop after enough ticks")
            let offsetFinal = scrollPanel.scrollOffset
            XCTAssertGreaterThanOrEqual(offsetFinal, offsetMid)
        }
    }

    func testMomentumOvershootsAndRubberBandsBackAtTopEdge() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 200))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 200))

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 80),
                layoutMode: .stack(.vertical(spacing: 10)),
                scrollAxis: .vertical,
                scrollOffset: 10,
                scrollStep: 20,
                isHitTestVisible: false,
                children: [itemA, itemB]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [scrollPanel])
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()
            XCTAssertEqual(scrollPanel.scrollOffset, 10)
            XCTAssertEqual(scrollPanel.scrollOvershoot, 0)

            // Scroll up hard (positive delta = toward 0). Velocity points
            // toward the top edge.
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: 5, source: .precise)
            XCTAssertEqual(scrollPanel.scrollOffset, 0, "Wheel clamps logical offset at top")

            let t0 = Win32Window.currentTimestampSeconds()
            // Drive ticks; momentum can't move offset further but should push
            // into rubber-band overshoot (negative since we're at the top).
            var t = t0
            var sawOvershoot = false
            for _ in 0..<10 {
                t += 0.016
                _ = runtime.tickAnimations(at: t)
                if scrollPanel.scrollOvershoot < 0 {
                    sawOvershoot = true
                }
            }
            XCTAssertTrue(sawOvershoot, "Momentum past the top edge should produce negative overshoot")

            // After enough simulated frames, overshoot springs back to 0.
            var ticks = 0
            while runtime.hasActiveAnimations, ticks < 240 {
                t += 0.016
                _ = runtime.tickAnimations(at: t)
                ticks += 1
            }
            XCTAssertEqual(scrollPanel.scrollOvershoot, 0, "Rubber-band must settle to 0")
            XCTAssertEqual(scrollPanel.scrollOffset, 0)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    /// A pressed control keeps its geometry. macOS answers a press with the
    /// bezel fill and nothing else — `NSButtonCell` highlights in the frame it
    /// already had — so a press installs no transform animation at all, and
    /// the node the painter sees is the node it saw at rest.
    ///
    /// This used to be a 0.97 shrink, pinned in three places as "the Big Sur
    /// feel". It is an iOS / custom-`ButtonStyle` idiom; see E6-PRESS in
    /// docs/AnimationParity.md.
    func testButtonPressChangesFillWithoutMovingGeometry() async {
        await MainActor.run {
            let palette = SurfacePalette(
                idle: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                focused: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                pressed: Color(red: 0.5, green: 0.6, blue: 0.7, alpha: 1)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 50), isHitTestVisible: false)
            let runtime = RetainedViewRuntime(root: root)
            let frame = Rect(x: 10, y: 8, width: 40, height: 24)
            let button = Controls.button(
                runtime: runtime,
                frame: frame,
                cornerRadius: 4,
                palette: palette,
                chrome: SurfaceChrome(),
                animation: ControlAnimationStyle(focusDuration: 0.12, pressDuration: 0.1),
                action: {}
            )
            root.addChild(button)
            XCTAssertEqual(button.transform.scaleX, 1.0)

            runtime.pointerDown(at: Point(x: 20, y: 16))
            XCTAssertEqual(button.transform.scaleX, 1.0, accuracy: 0.0001, "a pressed control is not scaled")
            XCTAssertEqual(button.transform.scaleY, 1.0, accuracy: 0.0001, "a pressed control is not scaled")
            XCTAssertNil(
                button.animationStates[.transformScaleX],
                "no transform tween is installed for a press at all — the default control costs the runtime nothing "
                    + "geometric under the pointer")
            XCTAssertNil(button.animationStates[.transformScaleY])
            XCTAssertNil(button.animationStates[.opacity], "a bordered ramp changes its fill, not its content")
            XCTAssertEqual(button.frame, frame, "the frame under the pointer is the frame at rest")
            // The press *is* visible: the fill ramp settles on its pressed rung.
            runtime.tickAnimations(at: 1e12)
            XCTAssertEqual(button.backgroundColor?.red ?? 0, palette.pressed.red, accuracy: 0.001)
            XCTAssertEqual(button.backgroundColor?.green ?? 0, palette.pressed.green, accuracy: 0.001)
            XCTAssertEqual(button.backgroundColor?.blue ?? 0, palette.pressed.blue, accuracy: 0.001)

            runtime.pointerUp(at: Point(x: 20, y: 16))
            XCTAssertEqual(button.transform.scaleX, 1.0, accuracy: 0.0001)
            XCTAssertEqual(button.transform.scaleY, 1.0, accuracy: 0.0001)
        }
    }

    /// The shrink machinery survives the parity decision: a style that asks
    /// for a press scale still gets one, down on press and back on release.
    func testButtonPressScaleIsOptInPerStyle() async {
        await MainActor.run {
            let clock = RuntimeTestClock()
            clock.now = 10
            let palette = SurfacePalette(
                idle: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                focused: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                pressed: Color(red: 0.5, green: 0.6, blue: 0.7, alpha: 1)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 50), isHitTestVisible: false)
            let runtime = RetainedViewRuntime(root: root)
            let button = Controls.button(
                runtime: runtime,
                frame: Rect(x: 10, y: 8, width: 40, height: 24),
                cornerRadius: 4,
                palette: palette,
                chrome: SurfaceChrome(),
                animation: ControlAnimationStyle(
                    focusDuration: 0.12,
                    pressDuration: 0.1,
                    pressedScale: ControlAnimationStyle.tactilePressedScale
                ),
                action: {}
            )
            root.addChild(button)
            XCTAssertEqual(button.transform.scaleX, 1.0)

            runtime.clock = { clock.now }
            runtime.pointerDown(at: Point(x: 20, y: 16))
            XCTAssertEqual(button.transform.scaleX, 1.0, "The first press frame keeps the presented scale")
            XCTAssertEqual(button.transform.scaleY, 1.0)
            XCTAssertEqual(
                button.animationStates[.transformScaleX]?.endValue, ControlAnimationStyle.tactilePressedScale)

            clock.now = 10.101
            _ = runtime.tickAnimations(at: clock.now)
            XCTAssertEqual(button.transform.scaleX, ControlAnimationStyle.tactilePressedScale, accuracy: 0.001)
            XCTAssertEqual(button.transform.scaleY, ControlAnimationStyle.tactilePressedScale, accuracy: 0.001)

            // Releasing starts the return from the pressed presentation value.
            runtime.pointerUp(at: Point(x: 20, y: 16))
            XCTAssertEqual(button.transform.scaleX, ControlAnimationStyle.tactilePressedScale, accuracy: 0.001)
            clock.now = 10.222
            _ = runtime.tickAnimations(at: clock.now)
            XCTAssertEqual(button.transform.scaleX, 1.0, accuracy: 0.001)
            XCTAssertEqual(button.transform.scaleY, 1.0, accuracy: 0.001)
        }
    }

    /// A borderless ramp has no fill to move, so it dims its content instead —
    /// AppKit's `contentsCellMask` highlight. Without this a `.plain` button
    /// would not acknowledge the pointer at all once the shrink was removed.
    func testBorderlessButtonPressDimsItsContent() async {
        await MainActor.run {
            let clock = RuntimeTestClock()
            clock.now = 10
            let palette = SurfacePalette(
                idle: .clear,
                hovered: .clear,
                focused: .clear,
                pressed: .clear,
                pressedContentOpacity: 0.72
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 50), isHitTestVisible: false)
            let runtime = RetainedViewRuntime(root: root)
            let button = Controls.button(
                runtime: runtime,
                frame: Rect(x: 10, y: 8, width: 40, height: 24),
                cornerRadius: 0,
                palette: palette,
                chrome: SurfaceChrome(),
                action: {}
            )
            root.addChild(button)
            XCTAssertEqual(button.opacity, 1.0, accuracy: 0.0001)

            runtime.clock = { clock.now }
            runtime.pointerDown(at: Point(x: 20, y: 16))
            XCTAssertEqual(button.opacity, 1.0, "The first press frame keeps the presented opacity")
            XCTAssertEqual(button.animationStates[.opacity]?.endValue, 0.72)
            XCTAssertEqual(button.transform.scaleX, 1.0, accuracy: 0.0001, "still no geometry change")

            clock.now = 10.141
            _ = runtime.tickAnimations(at: clock.now)
            XCTAssertEqual(button.opacity, 0.72, accuracy: 0.0001)
            runtime.pointerUp(at: Point(x: 20, y: 16))
            XCTAssertEqual(button.opacity, 0.72, accuracy: 0.0001)
            clock.now = 10.322
            _ = runtime.tickAnimations(at: clock.now)
            XCTAssertEqual(button.opacity, 1.0, accuracy: 0.0001)
        }
    }

    func testKeyboardScrollAnimatesViewportLag() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 200))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 200))

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 80),
                layoutMode: .stack(.vertical(spacing: 10)),
                scrollAxis: .vertical,
                scrollOffset: 0,
                scrollStep: 30,
                isFocusable: true,
                isHitTestVisible: false,
                children: [itemA, itemB]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [scrollPanel])
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()
            runtime.pointerMoved(to: Point(x: 30, y: 30))
            XCTAssertEqual(scrollPanel.scrollPresentedDelta, 0)

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            // Logical offset jumps immediately so callers observing
            // `scrollOffset` see the new value.
            XCTAssertEqual(scrollPanel.scrollOffset, 30)
            // Visual lag delta starts at -30 (rendered position lags behind).
            XCTAssertEqual(scrollPanel.scrollPresentedDelta, -30, accuracy: 0.001)
            XCTAssertTrue(runtime.hasActiveAnimations)

            // After the tween duration, delta is fully resolved.
            var t = Win32Window.currentTimestampSeconds()
            var ticks = 0
            while runtime.hasActiveAnimations, ticks < 120 {
                t += 0.016
                _ = runtime.tickAnimations(at: t)
                ticks += 1
            }
            XCTAssertEqual(scrollPanel.scrollPresentedDelta, 0)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testKeyboardScrollCancelsActiveMomentum() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 200))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 200))

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 80),
                layoutMode: .stack(.vertical(spacing: 10)),
                scrollAxis: .vertical,
                scrollStep: 20,
                isFocusable: true,
                isHitTestVisible: false,
                children: [itemA, itemB]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [scrollPanel])
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()
            runtime.pointerMoved(to: Point(x: 30, y: 30))
            runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -3, source: .precise)
            let offsetAfterWheel = scrollPanel.scrollOffset
            XCTAssertTrue(runtime.hasActiveAnimations)

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            // Logical offset advanced by exactly one scrollStep — the wheel
            // momentum from the prior input was cancelled, otherwise the
            // ongoing decay would have nudged offset further between events.
            XCTAssertEqual(
                scrollPanel.scrollOffset, offsetAfterWheel + scrollPanel.scrollStep,
                "Keyboard scroll should cancel wheel momentum and produce exactly one step of motion")
        }
    }

    func testHorizontalMouseWheelTargetsHorizontalScrollableAncestor() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 30))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 30))
            let itemC = ViewNode(
                backgroundColor: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                preferredSize: Size(width: 60, height: 30))

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 90, height: 40),
                layoutMode: .stack(
                    .horizontal(spacing: 10, padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5))),
                scrollAxis: .horizontal,
                scrollStep: 20,
                showsScrollIndicator: true,
                isHitTestVisible: false,
                children: [itemA, itemB, itemC]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 80), isHitTestVisible: false, children: [scrollPanel])
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()

            runtime.mouseWheel(at: Point(x: 40, y: 30), delta: -1, axis: .horizontal)
            XCTAssertEqual(scrollPanel.scrollOffset, 20)

            runtime.mouseWheel(at: Point(x: 40, y: 30), delta: 10, axis: .horizontal)
            XCTAssertEqual(scrollPanel.scrollOffset, 0)
        }
    }

    func testRenderFrameAppliesScrollOffsetAndDrawsScrollIndicator() async {
        await MainActor.run {
            let indicatorColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 0.3)
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 30))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 30))
            let itemC = ViewNode(
                backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                preferredSize: Size(width: 60, height: 30))

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 70),
                layoutMode: .stack(
                    .vertical(spacing: 10, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                scrollIndicatorColor: indicatorColor,
                isHitTestVisible: false,
                children: [itemA, itemB, itemC]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [scrollPanel])
            let runtime = RetainedViewRuntime(root: root)

            let fills = fillRectCommands(in: runtime.renderFrame())

            XCTAssertEqual(fills[0].rect, Rect(x: 20, y: 0, width: 60, height: 30))
            XCTAssertEqual(fills[1].rect, Rect(x: 20, y: 40, width: 60, height: 30))
            XCTAssertEqual(fills[2].rect, Rect(x: 20, y: 80, width: 60, height: 30))
            XCTAssertEqual(fills.last?.color, indicatorColor)
        }
    }

    func testDefaultScrollAnchorsResolveToRetainedScrollOffsetsAfterLayout() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 40, height: 40))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 40, height: 40))
            let itemC = ViewNode(
                backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                preferredSize: Size(width: 40, height: 40)
            )
            let scrollPanel = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 50),
                layoutMode: .stack(.vertical(alignment: .stretch)),
                scrollAxis: .vertical,
                initialScrollAnchor: RetainedScrollAnchor(x: 0.5, y: 1),
                scrollSizeChangeAnchor: RetainedScrollAnchor(x: 0.5, y: 1),
                isHitTestVisible: false,
                children: [itemA, itemB, itemC]
            )
            let runtime = RetainedViewRuntime(root: scrollPanel)

            _ = runtime.renderFrame()
            XCTAssertEqual(scrollPanel.scrollOffset, 70)

            scrollPanel.scrollOffset = 10
            _ = runtime.renderFrame()
            XCTAssertEqual(scrollPanel.scrollOffset, 10)

            itemC.preferredSize = Size(width: 40, height: 80)
            _ = runtime.renderFrame()
            XCTAssertEqual(scrollPanel.scrollOffset, 110)
        }
    }

    func testScrollIndicatorHoverAndDragUpdateColorAndOffset() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 30))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 30))
            let itemC = ViewNode(
                backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                preferredSize: Size(width: 60, height: 30))

            let idleColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 0.3)
            let hoverColor = Color(red: 0.9, green: 0.95, blue: 1, alpha: 0.55)
            let activeColor = Color(red: 1, green: 1, blue: 1, alpha: 0.8)

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 70),
                layoutMode: .stack(
                    .vertical(spacing: 10, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))),
                scrollAxis: .vertical,
                showsScrollIndicator: true,
                scrollIndicatorColor: idleColor,
                scrollIndicatorHoverColor: hoverColor,
                scrollIndicatorActiveColor: activeColor,
                isHitTestVisible: false,
                children: [itemA, itemB, itemC]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [scrollPanel])
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
                layoutMode: .stack(
                    .vertical(padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8), alignment: .leading)),
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
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 60), isHitTestVisible: false, children: [label])
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

    func testRedactedTextDrawsPlaceholderInsteadOfGlyphs() async {
        await MainActor.run {
            let label = Controls.label(
                "SECRET", frame: Rect(x: 10, y: 10, width: 80, height: 24), color: .white, scale: 2, alignment: .leading
            )
            label.redactionReasons = [.placeholder]
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 60), isHitTestVisible: false, children: [label])
            let runtime = RetainedViewRuntime(root: root)

            let frame = runtime.renderFrame()
            let hasBitmapCommand = frame.commands.contains { command in
                if case .drawBitmap = command {
                    return true
                }
                return false
            }
            let fills = fillRectCommands(in: frame)

            XCTAssertFalse(hasBitmapCommand)
            XCTAssertEqual(fills.count, 1)
            XCTAssertEqual(fills[0].rect, Rect(x: 10, y: 10, width: 80, height: 24))
            XCTAssertEqual(fills[0].color, retainedRedactionPlaceholderBaseColor)
            XCTAssertEqual(fills[0].cornerRadius, 6)

            let scene = runtime.renderScene()
            XCTAssertEqual(scene.layers.flatMap(\.glyphs).count, 0)
            XCTAssertEqual(scene.layers.flatMap(\.pixelGlyphs).count, 0)
            XCTAssertEqual(scene.layers.flatMap(\.quads).count, 1)
            XCTAssertEqual(scene.layers[0].quads[0].startA, Float(retainedRedactionPlaceholderBaseColor.alpha))
        }
    }

    func testDisplayScaleIncreasesRenderedBitmapResolution() async {
        await MainActor.run {
            let label = Controls.label(
                "HELLO", frame: Rect(x: 10, y: 10, width: 80, height: 24), color: .white, scale: 2, alignment: .leading)
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 60), isHitTestVisible: false, children: [label])
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

    func testBitmapNodeMeasuresAndRendersThroughFrameAndScene() async {
        await MainActor.run {
            let bitmap = BitmapSurface(
                width: 2,
                height: 1,
                bytesPerRow: 8,
                pixels: Data([0, 0, 255, 255, 0, 255, 0, 255])
            )
            let image = Controls.image(bitmap)
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 20, height: 10),
                layoutMode: .stack(.vertical()),
                isHitTestVisible: false,
                children: [image]
            )
            let runtime = RetainedViewRuntime(root: root)

            XCTAssertEqual(image.intrinsicContentSize(), Size(width: 2, height: 1))

            let bitmapCommand = runtime.renderFrame().commands.first { command in
                if case .drawBitmap = command {
                    return true
                }
                return false
            }
            guard case .drawBitmap(let drawBitmap)? = bitmapCommand else {
                return XCTFail("Expected bitmap image command")
            }
            XCTAssertEqual(drawBitmap.rect.size, Size(width: 2, height: 1))
            XCTAssertEqual(drawBitmap.bitmap, bitmap)

            let scene = runtime.renderScene()
            let imagePrimitives = scene.layers.flatMap(\.images)
            XCTAssertEqual(imagePrimitives.count, 1)
            XCTAssertEqual(scene.imageResources, [ImageResourceBinding(textureID: 0, bitmap: bitmap)])
            XCTAssertEqual(imagePrimitives[0].screenW, 2)
            XCTAssertEqual(imagePrimitives[0].screenH, 1)
            XCTAssertEqual(imagePrimitives[0].textureID, 0)
        }
    }

    func testBackgroundGradientFlowsIntoFillRectCommand() async {
        await MainActor.run {
            let gradient = SwiftWindowsGraphics.LinearGradient(
                startColor: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
                endColor: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                axis: .horizontal
            )
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40), backgroundColor: gradient.startColor,
                backgroundGradient: .linear(gradient))
            let runtime = RetainedViewRuntime(root: node)

            let fills = fillRectCommands(in: runtime.renderFrame())

            XCTAssertEqual(fills.count, 1)
            XCTAssertEqual(fills[0].gradient, .linear(gradient))
        }
    }

    func testBorderGradientFlowsIntoFillRectCommand() async {
        await MainActor.run {
            let gradient = SwiftWindowsGraphics.LinearGradient(
                startColor: Color(red: 0.9, green: 0.2, blue: 0.1, alpha: 1),
                endColor: Color(red: 0.1, green: 0.3, blue: 0.9, alpha: 0.7),
                axis: .vertical
            )
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                backgroundColor: .white,
                borderColor: gradient.startColor,
                borderGradient: .linear(gradient),
                borderWidth: 4
            )
            let runtime = RetainedViewRuntime(root: node)

            let fills = fillRectCommands(in: runtime.renderFrame())

            XCTAssertEqual(fills.count, 2)
            XCTAssertEqual(fills[0].gradient, .linear(gradient))
            XCTAssertNil(fills[1].gradient)
        }
    }

    func testBlurRadiusDoesNotEmitUnsupportedBlurCommand() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 40),
                backgroundColor: .white,
                blurRadius: 12
            )
            let runtime = RetainedViewRuntime(root: node)

            let frame = runtime.renderFrame()
            let hasBlurCommand = frame.commands.contains { command in
                if case .applyBlur = command {
                    return true
                }
                return false
            }

            XCTAssertFalse(hasBlurCommand)
            XCTAssertEqual(fillRectCommands(in: frame).count, 1)
        }
    }

    func testParentOpacityCascadesIntoChildFillCommands() async {
        await MainActor.run {
            let child = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 80),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                opacity: 0.4
            )
            let parent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                opacity: 0.5,
                children: [child]
            )
            let runtime = RetainedViewRuntime(root: parent)

            let fills = fillRectCommands(in: runtime.renderFrame())

            XCTAssertEqual(fills.count, 1)
            XCTAssertEqual(fills[0].color.alpha, 0.2, accuracy: 0.0001)
        }
    }

    func testRenderFrameReplaysUnchangedSiblingSubtree() async {
        await MainActor.run {
            let left = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
            )
            let right = ViewNode(
                frame: Rect(x: 50, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 60),
                children: [left, right]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()
            XCTAssertEqual(runtime.lastFrameReplayCount, 0)

            right.backgroundColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
            _ = runtime.renderFrame()

            XCTAssertEqual(runtime.lastFrameReplayCount, 1)
            XCTAssertEqual(left.subtreeDirtyFlags, [])
            XCTAssertEqual(right.subtreeDirtyFlags, [])
        }
    }

    func testRenderSceneReplaysUnchangedSiblingSubtree() async {
        await MainActor.run {
            let left = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
            )
            let right = ViewNode(
                frame: Rect(x: 50, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 60),
                children: [left, right]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderScene()
            XCTAssertEqual(runtime.lastSceneReplayCount, 0)

            right.backgroundColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
            _ = runtime.renderScene()

            XCTAssertEqual(runtime.lastSceneReplayCount, 1)
            XCTAssertEqual(left.subtreeDirtyFlags, [])
            XCTAssertEqual(right.subtreeDirtyFlags, [])
        }
    }

    func testPaintOnlyScrollUpdateReusesLayoutSubtreesAndStillMovesContent() async {
        await MainActor.run {
            var scrollLayouts = 0
            var contentLayouts = 0

            let content = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .white
            )
            content.onLayout = { _ in contentLayouts += 1 }

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 40),
                layoutMode: .absolute,
                scrollAxis: .vertical,
                showsScrollIndicator: true,
                isHitTestVisible: false,
                children: [content]
            )
            scrollPanel.onLayout = { _ in scrollLayouts += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 80),
                isHitTestVisible: false,
                children: [scrollPanel]
            )
            let runtime = RetainedViewRuntime(root: root)

            let initialFrame = runtime.renderFrame()
            XCTAssertEqual(scrollLayouts, 1)
            XCTAssertEqual(contentLayouts, 1)

            let initialContentRect = fillRectCommands(in: initialFrame).first(where: { $0.color == .white })?.rect
            XCTAssertNotNil(initialContentRect)
            XCTAssertEqual(initialContentRect?.origin.y, 10)

            scrollPanel.scrollOffset = 20
            let scrolledFrame = runtime.renderFrame()

            XCTAssertGreaterThanOrEqual(runtime.lastLayoutReuseCount, 2)
            XCTAssertEqual(scrollLayouts, 1)
            XCTAssertEqual(contentLayouts, 1)

            let scrolledContentRect = fillRectCommands(in: scrolledFrame).first(where: { $0.color == .white })?.rect
            XCTAssertNotNil(scrolledContentRect)
            XCTAssertEqual(scrolledContentRect?.origin.y, -10)
        }
    }

    func testDeferredScrollIndicatorsFlushAfterSiblingBaseContent() async {
        await MainActor.run {
            let leftIndicator = Color(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.6)
            let rightIndicator = Color(red: 0.2, green: 0.7, blue: 1.0, alpha: 0.6)

            let left = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                scrollIndicatorColor: leftIndicator,
                children: [ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 120), backgroundColor: .white)]
            )
            let right = ViewNode(
                frame: Rect(x: 90, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                scrollIndicatorColor: rightIndicator,
                children: [ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 120), backgroundColor: .black)]
            )

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 180, height: 70),
                isHitTestVisible: false,
                children: [left, right]
            )
            let runtime = RetainedViewRuntime(root: root)

            let fills = fillRectCommands(in: runtime.renderFrame())

            XCTAssertEqual(Array(fills.suffix(2).map(\.color)), [leftIndicator, rightIndicator])
        }
    }

    func testDeferredScrollIndicatorPrepaintReplaysUnchangedSiblingSubtree() async {
        await MainActor.run {
            let leftContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .white
            )
            let rightContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .black
            )

            let left = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                children: [leftContent]
            )
            let right = ViewNode(
                frame: Rect(x: 90, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                children: [rightContent]
            )

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 180, height: 70),
                isHitTestVisible: false,
                children: [left, right]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()
            XCTAssertEqual(runtime.lastDeferredOverlayReplayCount, 0)
            XCTAssertEqual(runtime.lastDeferredDrawFrameReplayCount, 0)

            rightContent.backgroundColor = Color(red: 0.1, green: 0.4, blue: 0.9, alpha: 1)
            _ = runtime.renderFrame()

            XCTAssertEqual(runtime.lastPrepaintReplayCount, 1)
            XCTAssertEqual(runtime.lastDeferredOverlayReplayCount, 1)
            XCTAssertEqual(runtime.lastDeferredDrawFrameReplayCount, 1)
        }
    }

    func testDeferredScrollIndicatorSceneReplayReusesUnchangedSiblingSubtree() async {
        await MainActor.run {
            let leftContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .white
            )
            let rightContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .black
            )

            let left = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                children: [leftContent]
            )
            let right = ViewNode(
                frame: Rect(x: 90, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                children: [rightContent]
            )

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 180, height: 70),
                isHitTestVisible: false,
                children: [left, right]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderScene()
            XCTAssertEqual(runtime.lastDeferredDrawSceneReplayCount, 0)

            rightContent.backgroundColor = Color(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
            _ = runtime.renderScene()

            XCTAssertEqual(runtime.lastPrepaintReplayCount, 1)
            XCTAssertEqual(runtime.lastDeferredDrawSceneReplayCount, 1)
        }
    }

    func testDeferredScrollIndicatorPayloadRerunsWhenSwitchingFromSceneToFramePath() async {
        await MainActor.run {
            let leftContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .white
            )
            let rightContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .black
            )

            let left = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                children: [leftContent]
            )
            let right = ViewNode(
                frame: Rect(x: 90, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                children: [rightContent]
            )

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 180, height: 70),
                isHitTestVisible: false,
                children: [left, right]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderScene()

            rightContent.backgroundColor = Color(red: 0.3, green: 0.4, blue: 0.7, alpha: 1)
            let frame = runtime.renderFrame()
            guard let expectedIndicatorRect = left.scrollIndicatorRect(in: Rect(x: 0, y: 0, width: 80, height: 50))
            else {
                XCTFail("expected scroll indicator")
                return
            }

            XCTAssertEqual(runtime.lastPrepaintReplayCount, 1)
            XCTAssertEqual(runtime.lastDeferredDrawFrameReplayCount, 0)
            XCTAssertTrue(fillRectCommands(in: frame).contains(where: { $0.rect == expectedIndicatorRect }))
        }
    }

    func testScrollIndicatorInsetsAffectRetainedIndicatorGeometry() async {
        await MainActor.run {
            let verticalContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .white
            )
            let vertical = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 0,
                showsScrollIndicator: true,
                scrollIndicatorThickness: 5,
                scrollIndicatorInsets: EdgeInsets(top: 10, leading: 4, bottom: 14, trailing: 8),
                children: [verticalContent]
            )
            let horizontalContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 50),
                backgroundColor: .black
            )
            let horizontal = ViewNode(
                frame: Rect(x: 0, y: 70, width: 80, height: 50),
                scrollAxis: .horizontal,
                scrollOffset: 0,
                showsScrollIndicator: true,
                scrollIndicatorThickness: 5,
                scrollIndicatorInsets: EdgeInsets(top: 3, leading: 7, bottom: 9, trailing: 11),
                children: [horizontalContent]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 90, height: 130),
                isHitTestVisible: false,
                children: [vertical, horizontal]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()

            XCTAssertEqual(
                vertical.scrollIndicatorRect(in: Rect(x: 0, y: 0, width: 80, height: 50)),
                Rect(x: 67, y: 10, width: 5, height: 24)
            )
            XCTAssertEqual(
                horizontal.scrollIndicatorRect(in: Rect(x: 0, y: 70, width: 80, height: 50)),
                Rect(x: 7, y: 106, width: 24.8, height: 5)
            )
        }
    }

    func testDeferredPhaseChildPaintsAfterBaseSiblings() async {
        await MainActor.run {
            let base = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: .white
            )
            let deferred = ViewNode(
                frame: Rect(x: 10, y: 10, width: 20, height: 20),
                backgroundColor: .black,
                paintsInDeferredPhase: true
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 60),
                isHitTestVisible: false,
                children: [base, deferred]
            )
            let runtime = RetainedViewRuntime(root: root)

            let commands = fillRectCommands(in: runtime.renderFrame())

            XCTAssertEqual(commands.map(\.rect), [base.frame, deferred.frame])
        }
    }

    func testDeferredPhaseChildParticipatesInPointerHitTesting() async {
        await MainActor.run {
            var pointerDowns = 0

            let deferred = ViewNode(
                frame: Rect(x: 10, y: 10, width: 20, height: 20),
                backgroundColor: .white,
                paintsInDeferredPhase: true
            )
            deferred.onPointerDown = { pointerDowns += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 60),
                isHitTestVisible: false,
                children: [deferred]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.pointerDown(at: Point(x: 15, y: 15))

            XCTAssertEqual(pointerDowns, 1)
        }
    }

    func testNestedDeferredPhaseSubtreesPaintInDeferredOrder() async {
        await MainActor.run {
            let deferredGrandchild = ViewNode(
                frame: Rect(x: 5, y: 5, width: 10, height: 10),
                backgroundColor: .black,
                paintsInDeferredPhase: true
            )
            let deferredChild = ViewNode(
                frame: Rect(x: 10, y: 10, width: 20, height: 20),
                backgroundColor: .white,
                isHitTestVisible: false,
                paintsInDeferredPhase: true,
                children: [deferredGrandchild]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 50, height: 50),
                isHitTestVisible: false,
                children: [deferredChild]
            )
            let runtime = RetainedViewRuntime(root: root)

            let commands = fillRectCommands(in: runtime.renderFrame())

            XCTAssertEqual(
                commands.map(\.rect),
                [
                    Rect(x: 10, y: 10, width: 20, height: 20),
                    Rect(x: 15, y: 15, width: 10, height: 10),
                ]
            )
        }
    }

    func testDeferredPhaseReplayKeepsNestedDeferredSubtreeOrdering() async {
        await MainActor.run {
            let base = ViewNode(
                frame: Rect(x: 0, y: 0, width: 12, height: 12),
                backgroundColor: .white
            )
            let deferredGrandchild = ViewNode(
                frame: Rect(x: 4, y: 4, width: 8, height: 8),
                backgroundColor: .black,
                paintsInDeferredPhase: true
            )
            let deferredChild = ViewNode(
                frame: Rect(x: 20, y: 20, width: 20, height: 20),
                backgroundColor: Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
                isHitTestVisible: false,
                paintsInDeferredPhase: true,
                children: [deferredGrandchild]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 60),
                isHitTestVisible: false,
                children: [base, deferredChild]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()

            base.backgroundColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 1)
            let frame = runtime.renderFrame()

            XCTAssertEqual(runtime.lastPrepaintReplayCount, 2)
            XCTAssertEqual(runtime.lastDeferredDrawFrameReplayCount, 2)
            XCTAssertEqual(
                fillRectCommands(in: frame).map(\.rect),
                [
                    base.frame,
                    Rect(x: 20, y: 20, width: 20, height: 20),
                    Rect(x: 24, y: 24, width: 8, height: 8),
                ]
            )
        }
    }

    func testScrollIndicatorHitUsesUpdatedPrepaintedOverlayGeometryWithoutRender() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 30))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 30))
            let itemC = ViewNode(
                backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                preferredSize: Size(width: 60, height: 30))

            let idleColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 0.3)
            let hoverColor = Color(red: 0.9, green: 0.95, blue: 1, alpha: 0.55)

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 70),
                layoutMode: .stack(
                    .vertical(spacing: 10, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))),
                scrollAxis: .vertical,
                showsScrollIndicator: true,
                scrollIndicatorColor: idleColor,
                scrollIndicatorHoverColor: hoverColor,
                isHitTestVisible: false,
                children: [itemA, itemB, itemC]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isHitTestVisible: false,
                children: [scrollPanel]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()
            scrollPanel.scrollOffset = 40

            runtime.pointerMoved(to: Point(x: 83, y: 50))
            _ = runtime.tickAnimations(at: Win32Window.currentTimestampSeconds() + 1)

            XCTAssertEqual(scrollPanel.scrollIndicatorColor, hoverColor)
        }
    }

    func testPrepaintHitTestingKeepsPaintOrderedZIndexPriority() async {
        await MainActor.run {
            var backPresses = 0
            var frontPresses = 0

            let back = ViewNode(
                frame: Rect(x: 10, y: 10, width: 60, height: 60),
                backgroundColor: .white
            )
            back.onPointerDown = { backPresses += 1 }

            let front = ViewNode(
                frame: Rect(x: 20, y: 20, width: 60, height: 60),
                backgroundColor: .black,
                zIndex: 1
            )
            front.onPointerDown = { frontPresses += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                children: [back, front]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.pointerDown(at: Point(x: 30, y: 30))

            XCTAssertEqual(frontPresses, 1)
            XCTAssertEqual(backPresses, 0)
        }
    }

    func testPrepaintHitTestingPreservesTransforms() async {
        await MainActor.run {
            var presses = 0

            let rotated = ViewNode(
                frame: Rect(x: 20, y: 20, width: 40, height: 40),
                backgroundColor: .white,
                transform: Transform2D(rotation: .pi / 4)
            )
            rotated.onPointerDown = { presses += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                children: [rotated]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.pointerDown(at: Point(x: 15, y: 40))

            XCTAssertEqual(presses, 1)
        }
    }

    func testParentRelayoutReusesCleanChildMeasurementCache() async {
        await MainActor.run {
            var childLayouts = 0

            let child = ViewNode(
                backgroundColor: .white,
                preferredSize: Size(width: 40, height: 20)
            )
            child.onLayout = { _ in childLayouts += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 80),
                layoutMode: .stack(.vertical(spacing: 8, alignment: .center)),
                isHitTestVisible: false,
                children: [child]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()
            XCTAssertEqual(childLayouts, 1)

            root.frame.size.height = 120
            _ = runtime.renderFrame()

            XCTAssertGreaterThan(runtime.lastMeasureReuseCount, 0)
            XCTAssertEqual(childLayouts, 1)
        }
    }

    func testMinimumFrameIntervalDefersSceneRefreshUntilEnoughTimeElapses() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
            )
            let runtime = RetainedViewRuntime(root: node)
            runtime.minimumFrameInterval = 1.0 / 60.0

            let firstScene = runtime.renderScene(at: 1.0)
            XCTAssertEqual(firstScene.layers[0].quads[0].startR, 1)
            XCTAssertFalse(runtime.isDirty)

            node.backgroundColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
            XCTAssertTrue(runtime.isDirty)

            let throttledScene = runtime.renderScene(at: 1.005)
            XCTAssertEqual(throttledScene, firstScene)
            XCTAssertTrue(runtime.isDirty)

            let refreshedScene = runtime.renderScene(at: 1.020)
            XCTAssertEqual(refreshedScene.layers[0].quads[0].startR, 0)
            XCTAssertEqual(refreshedScene.layers[0].quads[0].startB, 1)
            XCTAssertFalse(runtime.isDirty)
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

    func testPointerDownFocusesFocusableAncestorOfHitChild() async {
        await MainActor.run {
            var focusEvents: [String] = []
            var activations = 0

            let child = ViewNode(frame: Rect(x: 20, y: 20, width: 24, height: 24))
            let focusableParent = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 80),
                isFocusable: true,
                isHitTestVisible: false,
                children: [child]
            )
            focusableParent.onFocusEnter = { focusEvents.append("focus+") }
            focusableParent.onFocusExit = { focusEvents.append("focus-") }
            focusableParent.onActivate = { activations += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                isHitTestVisible: false,
                children: [focusableParent]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.pointerDown(at: Point(x: 35, y: 35))
            runtime.pointerUp(at: Point(x: 35, y: 35))
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
            runtime.keyboardFocusDidLeaveWindow()

            XCTAssertEqual(focusEvents, ["focus+", "focus-"])
            XCTAssertEqual(activations, 1)
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

    func testDraggableAncestorHandlesDragStartedFromHitChild() async {
        await MainActor.run {
            var startPoints: [Point] = []
            var dragDeltas: [Point] = []
            var endDeltas: [Point] = []

            let child = ViewNode(frame: Rect(x: 8, y: 8, width: 24, height: 24))
            let draggableParent = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 80),
                isHitTestVisible: false,
                children: [child]
            )
            draggableParent.onDragStart = { point in startPoints.append(point) }
            draggableParent.onDragChange = { _, delta in dragDeltas.append(delta) }
            draggableParent.onDragEnd = { _, delta in endDeltas.append(delta) }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                isHitTestVisible: false,
                children: [draggableParent]
            )
            let runtime = RetainedViewRuntime(root: root)

            runtime.pointerDown(at: Point(x: 24, y: 26))
            runtime.pointerMoved(to: Point(x: 46, y: 58))
            runtime.pointerUp(at: Point(x: 46, y: 58))

            XCTAssertEqual(startPoints, [Point(x: 24, y: 26)])
            XCTAssertEqual(dragDeltas.last, Point(x: 22, y: 32))
            XCTAssertEqual(endDeltas, [Point(x: 22, y: 32)])
        }
    }

    // MARK: - VAL-PARITY-001: Localized mutations change only the mutated region on both paths

    func testLocalizedMutationChangesOnlyMutatedRegionOnBothPaths() async {
        await MainActor.run {
            // Arrange: Create two sibling nodes
            let left = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
            )
            let right = ViewNode(
                frame: Rect(x: 50, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 60),
                children: [left, right]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Test frame path independently
            let initialFrame = runtime.renderFrame()  // Initial frame
            let initialFrameRects = fillRectCommands(in: initialFrame).map(\.rect)
            let initialFrameColors = fillRectCommands(in: initialFrame).map(\.color)

            right.backgroundColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
            let mutatedFrame = runtime.renderFrame()
            let frameReplayCount = runtime.lastFrameReplayCount
            let finalFrameRects = fillRectCommands(in: mutatedFrame).map(\.rect)
            let finalFrameColors = fillRectCommands(in: mutatedFrame).map(\.color)

            // Test scene path independently (on fresh runtime)
            let left2 = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
            )
            let right2 = ViewNode(
                frame: Rect(x: 50, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1)
            )
            let root2 = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 60),
                children: [left2, right2]
            )
            let runtime2 = RetainedViewRuntime(root: root2)

            let initialScene = runtime2.renderScene()  // Initial scene
            let initialSceneRects = sceneFillRects(in: initialScene)
            let initialSceneColors = sceneQuadColors(in: initialScene)

            right2.backgroundColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
            let mutatedScene = runtime2.renderScene()
            let sceneReplayCount = runtime2.lastSceneReplayCount
            let finalSceneRects = sceneFillRects(in: mutatedScene)
            let finalSceneColors = sceneQuadColors(in: mutatedScene)

            // Assert: Both paths show replay occurred for unchanged sibling
            XCTAssertEqual(frameReplayCount, 1, "Frame path should replay unchanged left sibling")
            XCTAssertEqual(sceneReplayCount, 1, "Scene path should replay unchanged left sibling")

            // Assert: Unchanged sibling (left) geometry and color preserved BEFORE mutation
            XCTAssertEqual(initialFrameRects[0], left.frame, "Frame: initial left geometry preserved")
            XCTAssertEqual(initialSceneRects[0], left2.frame, "Scene: initial left geometry preserved")
            XCTAssertEqual(
                initialFrameColors[0], Color(red: 1, green: 0, blue: 0, alpha: 1), "Frame: initial left color is red")
            XCTAssertEqual(
                initialSceneColors[0], Color(red: 1, green: 0, blue: 0, alpha: 1), "Scene: initial left color is red")

            // Assert: Unchanged sibling (left) geometry and color preserved AFTER mutation
            // The unchanged left sibling should have exactly the same rect and color as before
            XCTAssertEqual(finalFrameRects[0], left.frame, "Frame: final left geometry matches original")
            XCTAssertEqual(finalSceneRects[0], left2.frame, "Scene: final left geometry matches original")
            XCTAssertEqual(
                finalFrameColors[0], Color(red: 1, green: 0, blue: 0, alpha: 1),
                "Frame: final left color preserved as red")
            XCTAssertEqual(
                finalSceneColors[0], Color(red: 1, green: 0, blue: 0, alpha: 1),
                "Scene: final left color preserved as red")

            // Assert: Pre- and post-mutation normalized output comparison for unchanged sibling
            // Geometry: unchanged sibling rect should be identical before and after mutation on both paths
            XCTAssertEqual(
                initialFrameRects[0], finalFrameRects[0],
                "Frame: unchanged sibling geometry identical pre/post-mutation")
            XCTAssertEqual(
                initialSceneRects[0], finalSceneRects[0],
                "Scene: unchanged sibling geometry identical pre/post-mutation")
            XCTAssertEqual(
                initialFrameColors[0], finalFrameColors[0], "Frame: unchanged sibling color identical pre/post-mutation"
            )
            XCTAssertEqual(
                initialSceneColors[0], finalSceneColors[0], "Scene: unchanged sibling color identical pre/post-mutation"
            )

            // Assert: Mutated node (right) geometry unchanged, color changed on both paths
            XCTAssertEqual(finalFrameRects[1], right.frame, "Right node rect should match between paths")
            XCTAssertEqual(finalSceneRects[1], right2.frame, "Right node rect should match between paths")
            XCTAssertEqual(
                finalFrameColors[1], Color(red: 0, green: 0, blue: 1, alpha: 1),
                "Right node color should be blue in frame")
            XCTAssertEqual(
                finalSceneColors[1], Color(red: 0, green: 0, blue: 1, alpha: 1),
                "Right node color should be blue in scene")

            // Assert: Only the right node was regenerated, not the left
            XCTAssertEqual(finalFrameRects.count, 2, "Frame should still have exactly 2 fill rects")
            XCTAssertEqual(finalSceneRects.count, 2, "Scene should still have exactly 2 quads")

            // Assert: Both paths produce equivalent geometry for mutated region
            XCTAssertEqual(finalFrameRects[1], finalSceneRects[1], "Right node rect equivalent between frame and scene")

            // VAL-PARITY-001 EVIDENCE: Normalized output comparison showing unchanged sibling equivalence
            // Create normalized output representations for comparison
            let normalizedInitialFrame = NormalizedOutput(rects: initialFrameRects, colors: initialFrameColors)
            let normalizedFinalFrame = NormalizedOutput(rects: finalFrameRects, colors: finalFrameColors)
            let normalizedInitialScene = NormalizedOutput(rects: initialSceneRects, colors: initialSceneColors)
            let normalizedFinalScene = NormalizedOutput(rects: finalSceneRects, colors: finalSceneColors)

            // Unchanged sibling (index 0) should have identical normalized output before and after mutation
            XCTAssertEqual(
                normalizedInitialFrame.normalizedRects[0], normalizedFinalFrame.normalizedRects[0],
                "VAL-PARITY-001: Frame unchanged sibling normalized geometry equivalent pre/post-mutation")
            XCTAssertEqual(
                normalizedInitialFrame.normalizedColors[0], normalizedFinalFrame.normalizedColors[0],
                "VAL-PARITY-001: Frame unchanged sibling normalized color equivalent pre/post-mutation")
            XCTAssertEqual(
                normalizedInitialScene.normalizedRects[0], normalizedFinalScene.normalizedRects[0],
                "VAL-PARITY-001: Scene unchanged sibling normalized geometry equivalent pre/post-mutation")
            XCTAssertEqual(
                normalizedInitialScene.normalizedColors[0], normalizedFinalScene.normalizedColors[0],
                "VAL-PARITY-001: Scene unchanged sibling normalized color equivalent pre/post-mutation")

            // Mutated sibling (index 1) should show color change but geometry preservation
            XCTAssertEqual(
                normalizedInitialFrame.normalizedRects[1], normalizedFinalFrame.normalizedRects[1],
                "VAL-PARITY-001: Mutated node geometry preserved in frame")
            XCTAssertEqual(
                normalizedInitialScene.normalizedRects[1], normalizedFinalScene.normalizedRects[1],
                "VAL-PARITY-001: Mutated node geometry preserved in scene")
            XCTAssertNotEqual(
                normalizedInitialFrame.normalizedColors[1], normalizedFinalFrame.normalizedColors[1],
                "VAL-PARITY-001: Mutated node color changed in frame")
            XCTAssertNotEqual(
                normalizedInitialScene.normalizedColors[1], normalizedFinalScene.normalizedColors[1],
                "VAL-PARITY-001: Mutated node color changed in scene")
        }
    }

    // MARK: - VAL-PARITY-002: Unchanged sibling subtrees replay on both paths

    func testUnchangedSiblingSubtreesReplayOnBothPaths() async {
        await MainActor.run {
            // Test frame path independently
            let leftChild = ViewNode(
                frame: Rect(x: 5, y: 5, width: 20, height: 20),
                backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1)
            )
            let left = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                children: [leftChild]
            )
            let rightChild = ViewNode(
                frame: Rect(x: 5, y: 5, width: 20, height: 20),
                backgroundColor: Color(red: 0, green: 0, blue: 0, alpha: 1)
            )
            let right = ViewNode(
                frame: Rect(x: 50, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
                children: [rightChild]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 60),
                children: [left, right]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderFrame()
            rightChild.backgroundColor = Color(red: 1, green: 1, blue: 0, alpha: 1)
            let frameAfterMutation = runtime.renderFrame()
            let frameReplayCount = runtime.lastFrameReplayCount
            let frameRects = fillRectCommands(in: frameAfterMutation).map(\.rect)
            let frameColors = fillRectCommands(in: frameAfterMutation).map(\.color)

            // Test scene path independently (on fresh runtime)
            let leftChild2 = ViewNode(
                frame: Rect(x: 5, y: 5, width: 20, height: 20),
                backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1)
            )
            let left2 = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                children: [leftChild2]
            )
            let rightChild2 = ViewNode(
                frame: Rect(x: 5, y: 5, width: 20, height: 20),
                backgroundColor: Color(red: 0, green: 0, blue: 0, alpha: 1)
            )
            let right2 = ViewNode(
                frame: Rect(x: 50, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
                children: [rightChild2]
            )
            let root2 = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 60),
                children: [left2, right2]
            )
            let runtime2 = RetainedViewRuntime(root: root2)

            _ = runtime2.renderScene()
            rightChild2.backgroundColor = Color(red: 1, green: 1, blue: 0, alpha: 1)
            let sceneAfterMutation = runtime2.renderScene()
            let sceneReplayCount = runtime2.lastSceneReplayCount
            let sceneRects = sceneFillRects(in: sceneAfterMutation)
            let sceneColors = sceneQuadColors(in: sceneAfterMutation)

            // Assert: Both paths replayed unchanged left subtree
            XCTAssertEqual(frameReplayCount, 1, "Frame path should replay unchanged left subtree")
            XCTAssertEqual(sceneReplayCount, 1, "Scene path should replay unchanged left subtree")

            // Assert: Left subtree geometry preserved on both paths (may be in different order)
            // Both paths should contain the left parent frame (0,0,40,40)
            XCTAssertTrue(frameRects.contains(left.frame), "Left parent rect preserved in frame")
            XCTAssertTrue(sceneRects.contains(left2.frame), "Left parent rect preserved in scene")

            // Both paths should contain the left child frame (5,5,20,20)
            XCTAssertTrue(frameRects.contains(leftChild.frame), "Left child rect preserved in frame")
            XCTAssertTrue(sceneRects.contains(leftChild2.frame), "Left child rect preserved in scene")

            // Assert: Mutated node has new color on both paths
            XCTAssertEqual(
                frameColors[3], Color(red: 1, green: 1, blue: 0, alpha: 1), "Right child should have yellow in frame")
            XCTAssertEqual(
                sceneColors[3], Color(red: 1, green: 1, blue: 0, alpha: 1), "Right child should have yellow in scene")
        }
    }

    // MARK: - VAL-PARITY-003: Paint-only scroll updates reuse layout and update geometry on both paths

    func testPaintOnlyScrollUpdateReusesLayoutAndUpdatesGeometryOnBothPaths() async {
        await MainActor.run {
            // Use the SAME scrollable content for both frame and scene paths
            // so we can directly compare scroll deltas and indicator geometry
            var contentLayouts = 0
            var scrollLayouts = 0

            let content = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1)
            )
            content.onLayout = { _ in contentLayouts += 1 }

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 40),
                layoutMode: .absolute,
                scrollAxis: .vertical,
                showsScrollIndicator: true,
                isHitTestVisible: false,
                children: [content]
            )
            scrollPanel.onLayout = { _ in scrollLayouts += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 80),
                isHitTestVisible: false,
                children: [scrollPanel]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial render on both paths
            let initialFrame = runtime.renderFrame()
            let initialScene = runtime.renderScene()

            XCTAssertEqual(contentLayouts, 1, "Content should layout only once (shared)")
            XCTAssertEqual(scrollLayouts, 1, "Scroll panel should layout only once (shared)")

            // Capture initial content positions on BOTH paths
            let initialFrameContentY = fillRectCommands(in: initialFrame).first {
                $0.color == Color(red: 1, green: 1, blue: 1, alpha: 1)
            }?.rect.origin.y
            let initialSceneRects = sceneFillRects(in: initialScene)
            let initialSceneContentRect = initialSceneRects.first { rect in
                rect.size.height == 120  // content height
            }
            XCTAssertNotNil(initialFrameContentY, "Should find content in initial frame")
            XCTAssertNotNil(initialSceneContentRect, "Should find content in initial scene")

            // Capture initial indicator positions on BOTH paths
            let initialFrameIndicator = fillRectCommands(in: initialFrame).last
            let initialSceneQuads = initialScene.layers.flatMap { $0.quads }
            let initialSceneIndicator = initialSceneQuads.last

            // Apply paint-only scroll update
            scrollPanel.scrollOffset = 30

            // Render both paths after scroll
            let scrolledFrame = runtime.renderFrame()
            let scrolledScene = runtime.renderScene()

            // Assert: Layout reuse on both paths
            XCTAssertEqual(contentLayouts, 1, "Content should not relayout for paint-only scroll")
            XCTAssertEqual(scrollLayouts, 1, "Scroll panel should not relayout for paint-only scroll")
            XCTAssertGreaterThanOrEqual(runtime.lastLayoutReuseCount, 1, "Should show layout reuse")

            // ============================================================
            // VAL-PARITY-003: Direct frame-vs-scene scroll delta comparison
            // ============================================================

            // Frame path: Calculate scroll delta
            let scrolledFrameContentY = fillRectCommands(in: scrolledFrame).first {
                $0.color == Color(red: 1, green: 1, blue: 1, alpha: 1)
            }?.rect.origin.y
            XCTAssertNotNil(scrolledFrameContentY, "Should find content in scrolled frame")

            let frameScrollDelta = initialFrameContentY! - scrolledFrameContentY!
            XCTAssertEqual(frameScrollDelta, 30.0, accuracy: 0.001, "Frame: content should move by exact scroll offset")

            // Scene path: Calculate scroll delta
            let scrolledSceneRects = sceneFillRects(in: scrolledScene)
            let scrolledSceneContentRect = scrolledSceneRects.first { rect in
                rect.size.height == 120  // content height
            }
            XCTAssertNotNil(scrolledSceneContentRect, "Should find content in scrolled scene")

            let sceneScrollDeltaPixels = initialSceneContentRect!.origin.y - scrolledSceneContentRect!.origin.y
            let sceneScrollDelta = sceneScrollDeltaPixels / runtime.displayScale

            // DIRECT COMPARISON: Frame scroll delta vs Scene scroll delta (normalized)
            XCTAssertEqual(
                sceneScrollDelta, frameScrollDelta, accuracy: 0.001,
                "VAL-PARITY-003: Frame and scene scroll deltas must match directly - frame=\(frameScrollDelta), scene(normalized)=\(sceneScrollDelta)"
            )

            // ============================================================
            // VAL-PARITY-003: Direct frame-vs-scene indicator geometry comparison
            // ============================================================

            // Frame path: Calculate indicator position delta
            let scrolledFrameIndicator = fillRectCommands(in: scrolledFrame).last
            XCTAssertNotNil(initialFrameIndicator, "Should have initial frame indicator")
            XCTAssertNotNil(scrolledFrameIndicator, "Should have scrolled frame indicator")

            let frameIndicatorDeltaY = scrolledFrameIndicator!.rect.origin.y - initialFrameIndicator!.rect.origin.y
            let frameIndicatorHeight = initialFrameIndicator!.rect.size.height

            // Scene path: Calculate indicator position delta (normalized from device pixels)
            let scrolledSceneQuads = scrolledScene.layers.flatMap { $0.quads }
            let scrolledSceneIndicator = scrolledSceneQuads.last
            XCTAssertNotNil(initialSceneIndicator, "Should have initial scene indicator")
            XCTAssertNotNil(scrolledSceneIndicator, "Should have scrolled scene indicator")

            let initialSceneIndicatorY = Double(initialSceneIndicator!.y)
            let scrolledSceneIndicatorY = Double(scrolledSceneIndicator!.y)
            let sceneIndicatorDeltaYPixels = scrolledSceneIndicatorY - initialSceneIndicatorY
            let sceneIndicatorDeltaY = sceneIndicatorDeltaYPixels / runtime.displayScale

            // DIRECT COMPARISON: Frame indicator delta vs Scene indicator delta
            XCTAssertEqual(
                sceneIndicatorDeltaY, frameIndicatorDeltaY, accuracy: 0.001,
                "VAL-PARITY-003: Frame and scene indicator position deltas must match directly - frame=\(frameIndicatorDeltaY), scene(normalized)=\(sceneIndicatorDeltaY)"
            )

            // DIRECT COMPARISON: Indicator sizes (both should be same logical size)
            let initialSceneIndicatorHeightPixels = Double(initialSceneIndicator!.height)
            let sceneIndicatorHeight = initialSceneIndicatorHeightPixels / runtime.displayScale

            XCTAssertEqual(
                sceneIndicatorHeight, frameIndicatorHeight, accuracy: 0.001,
                "VAL-PARITY-003: Frame and scene indicator heights must match directly - frame=\(frameIndicatorHeight), scene(normalized)=\(sceneIndicatorHeight)"
            )

            // Both indicators should show movement in the same direction
            XCTAssertGreaterThan(frameIndicatorDeltaY, 0, "Frame indicator should move down after scroll")
            XCTAssertGreaterThan(sceneIndicatorDeltaY, 0, "Scene indicator should move down after scroll (normalized)")
        }
    }

    // MARK: - VAL-PARITY-004: Deferred overlays paint after base content on initial and replayed passes

    func testDeferredOverlaysPaintAfterBaseContentOnScenePath() async {
        await MainActor.run {
            let base = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: .white
            )
            let deferredOverlay = ViewNode(
                frame: Rect(x: 10, y: 10, width: 20, height: 20),
                backgroundColor: .black,
                paintsInDeferredPhase: true
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 60),
                isHitTestVisible: false,
                children: [base, deferredOverlay]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial scene paint
            let initialScene = runtime.renderScene()
            let initialQuads = sceneFillRects(in: initialScene)

            // Assert: base comes first, then deferred overlay
            XCTAssertEqual(initialQuads.count, 2)
            XCTAssertEqual(initialQuads[0], base.frame)
            XCTAssertEqual(initialQuads[1], deferredOverlay.frame)

            // Mutation elsewhere triggers replay
            base.backgroundColor = Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            let replayedScene = runtime.renderScene()
            let replayedQuads = sceneFillRects(in: replayedScene)

            // Assert: ordering preserved after replay
            XCTAssertEqual(replayedQuads.count, 2)
            XCTAssertEqual(replayedQuads[0], base.frame)
            XCTAssertEqual(replayedQuads[1], deferredOverlay.frame)
        }
    }

    func testDeferredOverlaySceneReplayReusesUnchangedSiblingSubtree() async {
        await MainActor.run {
            let leftContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .white
            )
            let rightContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .black
            )

            let left = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                children: [leftContent]
            )
            let right = ViewNode(
                frame: Rect(x: 90, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                children: [rightContent]
            )

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 180, height: 70),
                isHitTestVisible: false,
                children: [left, right]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderScene()
            XCTAssertEqual(runtime.lastDeferredDrawSceneReplayCount, 0)

            // Mutate right content only
            rightContent.backgroundColor = Color(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
            _ = runtime.renderScene()

            // Assert: Left subtree (including its scroll indicator) was replayed
            XCTAssertEqual(runtime.lastPrepaintReplayCount, 1)
            XCTAssertEqual(runtime.lastDeferredDrawSceneReplayCount, 1)
        }
    }

    // MARK: - VAL-PARITY-005: Nested deferred subtrees keep parent-before-child ordering on both paths

    func testNestedDeferredSceneSubtreesPreserveParentBeforeChildOrdering() async {
        await MainActor.run {
            let deferredGrandchild = ViewNode(
                frame: Rect(x: 5, y: 5, width: 10, height: 10),
                backgroundColor: .black,
                paintsInDeferredPhase: true
            )
            let deferredChild = ViewNode(
                frame: Rect(x: 10, y: 10, width: 20, height: 20),
                backgroundColor: .white,
                isHitTestVisible: false,
                paintsInDeferredPhase: true,
                children: [deferredGrandchild]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 50, height: 50),
                isHitTestVisible: false,
                children: [deferredChild]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial scene paint
            let initialScene = runtime.renderScene()
            let initialQuads = sceneFillRects(in: initialScene)

            // Assert: parent comes before child
            XCTAssertEqual(initialQuads.count, 2)
            XCTAssertEqual(initialQuads[0], deferredChild.frame)
            XCTAssertEqual(initialQuads[1], Rect(x: 15, y: 15, width: 10, height: 10))
        }
    }

    func testNestedDeferredSceneReplayPreservesParentBeforeChildOrdering() async {
        await MainActor.run {
            let base = ViewNode(
                frame: Rect(x: 0, y: 0, width: 12, height: 12),
                backgroundColor: .white
            )
            let deferredGrandchild = ViewNode(
                frame: Rect(x: 4, y: 4, width: 8, height: 8),
                backgroundColor: .black,
                paintsInDeferredPhase: true
            )
            let deferredChild = ViewNode(
                frame: Rect(x: 20, y: 20, width: 20, height: 20),
                backgroundColor: Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
                isHitTestVisible: false,
                paintsInDeferredPhase: true,
                children: [deferredGrandchild]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 60),
                isHitTestVisible: false,
                children: [base, deferredChild]
            )
            let runtime = RetainedViewRuntime(root: root)

            _ = runtime.renderScene()

            base.backgroundColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 1)
            let scene = runtime.renderScene()

            XCTAssertEqual(runtime.lastPrepaintReplayCount, 2)
            XCTAssertEqual(runtime.lastDeferredDrawSceneReplayCount, 2)

            let quads = sceneFillRects(in: scene)
            XCTAssertEqual(quads.count, 3)
            XCTAssertEqual(quads[0], base.frame)
            XCTAssertEqual(quads[1], deferredChild.frame)
            XCTAssertEqual(quads[2], Rect(x: 24, y: 24, width: 8, height: 8))
        }
    }

    // MARK: - VAL-PARITY-006: Scene-to-frame switching reruns incompatible deferred payloads safely

    func testSceneToFrameSwitchRerunsIncompatibleDeferredPayloads() async {
        await MainActor.run {
            let leftContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .white
            )
            let rightContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .black
            )

            let left = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                children: [leftContent]
            )
            let right = ViewNode(
                frame: Rect(x: 90, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                children: [rightContent]
            )

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 180, height: 70),
                isHitTestVisible: false,
                children: [left, right]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Start with scene path
            _ = runtime.renderScene()

            // Mutate content elsewhere
            rightContent.backgroundColor = Color(red: 0.3, green: 0.4, blue: 0.7, alpha: 1)

            // Switch to frame path
            let frame = runtime.renderFrame()
            guard let expectedIndicatorRect = left.scrollIndicatorRect(in: Rect(x: 0, y: 0, width: 80, height: 50))
            else {
                XCTFail("expected scroll indicator")
                return
            }

            // Assert: Prepainted data replayed, but deferred payload rerun for frame
            XCTAssertEqual(runtime.lastPrepaintReplayCount, 1)
            XCTAssertEqual(runtime.lastDeferredDrawFrameReplayCount, 0)
            XCTAssertTrue(fillRectCommands(in: frame).contains { $0.rect == expectedIndicatorRect })
        }
    }

    // MARK: - Backend-switch: .subtree deferred payload reruns

    func testSceneToFrameSwitchRerunsSubtreeDeferredPayload() async {
        await MainActor.run {
            let base = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: .white
            )
            let deferredGrandchild = ViewNode(
                frame: Rect(x: 4, y: 4, width: 8, height: 8),
                backgroundColor: .black,
                paintsInDeferredPhase: true
            )
            let deferredChild = ViewNode(
                frame: Rect(x: 20, y: 20, width: 20, height: 20),
                backgroundColor: Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
                isHitTestVisible: false,
                paintsInDeferredPhase: true,
                children: [deferredGrandchild]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 60),
                isHitTestVisible: false,
                children: [base, deferredChild]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Start with scene path - renders deferred subtree
            _ = runtime.renderScene()
            XCTAssertEqual(runtime.lastDeferredDrawSceneReplayCount, 0)

            // Mutate content elsewhere
            base.backgroundColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 1)

            // Switch to frame path - should rerun .subtree deferred payload
            let frame = runtime.renderFrame()

            // Assert: Prepainted data replayed, but subtree deferred payload was rerun for frame
            XCTAssertEqual(runtime.lastPrepaintReplayCount, 2)
            XCTAssertEqual(runtime.lastDeferredDrawFrameReplayCount, 0)

            // Verify: Frame contains all 3 quads including nested deferred subtree
            let frameRects = fillRectCommands(in: frame).map(\.rect)
            XCTAssertEqual(frameRects.count, 3)
            XCTAssertEqual(frameRects[0], base.frame)
            XCTAssertEqual(frameRects[1], deferredChild.frame)
            XCTAssertEqual(frameRects[2], Rect(x: 24, y: 24, width: 8, height: 8))
        }
    }

    func testFrameToSceneSwitchRerunsSubtreeDeferredPayload() async {
        await MainActor.run {
            let base = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: .white
            )
            let deferredGrandchild = ViewNode(
                frame: Rect(x: 4, y: 4, width: 8, height: 8),
                backgroundColor: .black,
                paintsInDeferredPhase: true
            )
            let deferredChild = ViewNode(
                frame: Rect(x: 20, y: 20, width: 20, height: 20),
                backgroundColor: Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
                isHitTestVisible: false,
                paintsInDeferredPhase: true,
                children: [deferredGrandchild]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 60),
                isHitTestVisible: false,
                children: [base, deferredChild]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Start with frame path - renders deferred subtree
            _ = runtime.renderFrame()
            XCTAssertEqual(runtime.lastDeferredDrawFrameReplayCount, 0)

            // Mutate content elsewhere
            base.backgroundColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 1)

            // Switch to scene path - should rerun .subtree deferred payload
            let scene = runtime.renderScene()

            // Assert: Prepainted data replayed, but subtree deferred payload was rerun for scene
            XCTAssertEqual(runtime.lastPrepaintReplayCount, 2)
            XCTAssertEqual(runtime.lastDeferredDrawSceneReplayCount, 0)

            // Verify: Scene contains all 3 quads including nested deferred subtree
            let quads = sceneFillRects(in: scene)
            XCTAssertEqual(quads.count, 3)
            XCTAssertEqual(quads[0], base.frame)
            XCTAssertEqual(quads[1], deferredChild.frame)
            XCTAssertEqual(quads[2], Rect(x: 24, y: 24, width: 8, height: 8))
        }
    }

    // MARK: - VAL-PARITY-008: Replayed prepaint metadata preserves z-order and transform hit testing

    func testReplayedPrepaintPreservesZOrderHitTesting() async {
        await MainActor.run {
            var backPresses = 0
            var frontPresses = 0

            let back = ViewNode(
                frame: Rect(x: 10, y: 10, width: 60, height: 60),
                backgroundColor: .white
            )
            back.onPointerDown = { backPresses += 1 }

            let front = ViewNode(
                frame: Rect(x: 20, y: 20, width: 60, height: 60),
                backgroundColor: .black,
                zIndex: 1
            )
            front.onPointerDown = { frontPresses += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                children: [back, front]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial render
            _ = runtime.renderFrame()

            // Mutate the back node to trigger replay
            back.backgroundColor = Color(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)

            // Re-render (should replay prepaint for unchanged front)
            _ = runtime.renderFrame()

            // Hit test in overlapping area - front should win due to z-order
            runtime.pointerDown(at: Point(x: 30, y: 30))

            XCTAssertEqual(frontPresses, 1, "Front node (higher z-index) should receive hit after replay")
            XCTAssertEqual(backPresses, 0, "Back node should not receive hit")
        }
    }

    func testReplayedPrepaintPreservesTransformHitTesting() async {
        await MainActor.run {
            var rotatedPresses = 0

            // Create a rotated 45-degree diamond shape
            let rotated = ViewNode(
                frame: Rect(x: 20, y: 20, width: 40, height: 40),
                backgroundColor: .white,
                transform: Transform2D(rotation: .pi / 4)
            )
            rotated.onPointerDown = { rotatedPresses += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                children: [rotated]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial render
            _ = runtime.renderFrame()

            // Mutate something to trigger replay
            rotated.backgroundColor = Color(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)

            // Re-render
            _ = runtime.renderFrame()

            // Hit test at a point that would be outside the axis-aligned bounds
            // but inside the rotated diamond
            runtime.pointerDown(at: Point(x: 15, y: 40))

            XCTAssertEqual(rotatedPresses, 1, "Rotated node should receive hit using transform after replay")
        }
    }

    // MARK: - VAL-PARITY-009: Descendant and deferred hits route the correct retained ancestors

    func testDescendantHitRoutesCorrectFocusableActivatableAncestor() async {
        await MainActor.run {
            var ancestorActivations = 0
            var childPresses = 0

            let child = ViewNode(
                frame: Rect(x: 20, y: 20, width: 40, height: 40),
                backgroundColor: .white
            )
            child.onPointerDown = { childPresses += 1 }

            let focusableAncestor = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 80),
                isFocusable: true,
                isHitTestVisible: false,
                children: [child]
            )
            focusableAncestor.onActivate = { ancestorActivations += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                isHitTestVisible: false,
                children: [focusableAncestor]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial render
            _ = runtime.renderFrame()

            // Hit the child to focus the ancestor
            runtime.pointerDown(at: Point(x: 35, y: 35))
            runtime.pointerUp(at: Point(x: 35, y: 35))

            // Activate via keyboard
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(childPresses, 1, "Child should receive pointer down")
            XCTAssertEqual(ancestorActivations, 1, "Ancestor should be activated via keyboard focus")
        }
    }

    func testDescendantHitRoutesCorrectDraggableAncestor() async {
        await MainActor.run {
            var dragStarts: [Point] = []
            var dragChanges: [Point] = []
            var endDeltas: [Point] = []

            let child = ViewNode(
                frame: Rect(x: 20, y: 20, width: 40, height: 40),
                backgroundColor: .white
            )

            let draggableAncestor = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 80),
                isHitTestVisible: false,
                children: [child]
            )
            draggableAncestor.onDragStart = { point in dragStarts.append(point) }
            draggableAncestor.onDragChange = { _, delta in dragChanges.append(delta) }
            draggableAncestor.onDragEnd = { _, delta in endDeltas.append(delta) }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                isHitTestVisible: false,
                children: [draggableAncestor]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial render
            _ = runtime.renderFrame()

            // Hit the child and drag - should route to draggable ancestor
            runtime.pointerDown(at: Point(x: 35, y: 35))
            runtime.pointerMoved(to: Point(x: 45, y: 55))
            runtime.pointerUp(at: Point(x: 45, y: 55))

            // VAL-PARITY-009: Draggable ancestor receives drag events from descendant hit
            XCTAssertEqual(
                dragStarts, [Point(x: 35, y: 35)], "Draggable ancestor should receive drag start from descendant hit")
            XCTAssertEqual(
                dragChanges.last, Point(x: 10, y: 20),
                "Draggable ancestor should receive drag change from descendant hit")
            XCTAssertEqual(
                endDeltas, [Point(x: 10, y: 20)], "Draggable ancestor should receive drag end from descendant hit")
        }
    }

    func testDescendantHitRoutesCorrectScrollableAncestor() async {
        await MainActor.run {
            let content = ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 200),
                backgroundColor: .white
            )

            let scrollableAncestor = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 80),
                scrollAxis: .vertical,
                scrollStep: 20,
                isHitTestVisible: false,
                children: [content]
            )

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                isHitTestVisible: false,
                children: [scrollableAncestor]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial render
            _ = runtime.renderFrame()

            // Hit the content and wheel scroll - should route to scrollable ancestor
            runtime.mouseWheel(at: Point(x: 35, y: 35), delta: -1)

            XCTAssertEqual(scrollableAncestor.scrollOffset, 20, "Scrollable ancestor should receive scroll wheel")
        }
    }

    func testDeferredHitRoutesCorrectFocusableActivatableAncestor() async {
        await MainActor.run {
            var deferredPresses = 0
            var parentActivations = 0

            let deferredChild = ViewNode(
                frame: Rect(x: 10, y: 10, width: 20, height: 20),
                backgroundColor: .white,
                paintsInDeferredPhase: true
            )
            deferredChild.onPointerDown = { deferredPresses += 1 }

            let focusableParent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 50, height: 50),
                isFocusable: true,
                isHitTestVisible: false,
                children: [deferredChild]
            )
            focusableParent.onActivate = { parentActivations += 1 }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isHitTestVisible: false,
                children: [focusableParent]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial render
            _ = runtime.renderFrame()

            // Hit the deferred child to focus the parent
            runtime.pointerDown(at: Point(x: 20, y: 20))
            runtime.pointerUp(at: Point(x: 20, y: 20))

            // Activate via keyboard
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

            XCTAssertEqual(deferredPresses, 1, "Deferred child should receive pointer down")
            XCTAssertEqual(parentActivations, 1, "Parent should be activated via keyboard focus")
        }
    }

    func testDeferredHitRoutesCorrectDraggableAncestor() async {
        await MainActor.run {
            var dragStarts: [Point] = []
            var dragChanges: [Point] = []
            var endDeltas: [Point] = []

            let deferredChild = ViewNode(
                frame: Rect(x: 10, y: 10, width: 20, height: 20),
                backgroundColor: .white,
                paintsInDeferredPhase: true
            )

            let draggableParent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 50, height: 50),
                isHitTestVisible: false,
                children: [deferredChild]
            )
            draggableParent.onDragStart = { point in dragStarts.append(point) }
            draggableParent.onDragChange = { _, delta in dragChanges.append(delta) }
            draggableParent.onDragEnd = { _, delta in endDeltas.append(delta) }

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isHitTestVisible: false,
                children: [draggableParent]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial render
            _ = runtime.renderFrame()

            // Hit the deferred child and drag - should route to draggable parent
            runtime.pointerDown(at: Point(x: 20, y: 20))
            runtime.pointerMoved(to: Point(x: 30, y: 40))
            runtime.pointerUp(at: Point(x: 30, y: 40))

            // VAL-PARITY-009: Draggable ancestor receives drag events from deferred-phase hit
            XCTAssertEqual(
                dragStarts, [Point(x: 20, y: 20)], "Draggable parent should receive drag start from deferred hit")
            XCTAssertEqual(
                dragChanges.last, Point(x: 10, y: 20), "Draggable parent should receive drag changes from deferred hit")
            XCTAssertEqual(
                endDeltas, [Point(x: 10, y: 20)], "Draggable parent should receive drag end from deferred hit")
        }
    }

    func testDeferredHitRoutesCorrectScrollableAncestor() async {
        await MainActor.run {
            let deferredContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 200),
                backgroundColor: .white,
                paintsInDeferredPhase: true
            )

            let scrollableParent = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 80),
                scrollAxis: .vertical,
                scrollStep: 25,
                isHitTestVisible: false,
                children: [deferredContent]
            )

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 120),
                isHitTestVisible: false,
                children: [scrollableParent]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial render
            _ = runtime.renderFrame()

            // Hit the deferred content and wheel scroll - should route to scrollable parent
            runtime.mouseWheel(at: Point(x: 35, y: 35), delta: -1)

            XCTAssertEqual(
                scrollableParent.scrollOffset, 25, "Scrollable parent should receive scroll wheel from deferred hit")
        }
    }

    // MARK: - VAL-PARITY-010: Updated overlay geometry is interactive before the next render

    func testUpdatedOverlayGeometryIsInteractiveBeforeRender() async {
        await MainActor.run {
            let itemA = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 30))
            let itemB = ViewNode(backgroundColor: .black, preferredSize: Size(width: 60, height: 30))
            let itemC = ViewNode(
                backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                preferredSize: Size(width: 60, height: 30))

            let idleColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 0.3)
            let hoverColor = Color(red: 0.9, green: 0.95, blue: 1, alpha: 0.55)

            let scrollPanel = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 70),
                layoutMode: .stack(
                    .vertical(spacing: 10, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))),
                scrollAxis: .vertical,
                showsScrollIndicator: true,
                scrollIndicatorColor: idleColor,
                scrollIndicatorHoverColor: hoverColor,
                isHitTestVisible: false,
                children: [itemA, itemB, itemC]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isHitTestVisible: false,
                children: [scrollPanel]
            )
            let runtime = RetainedViewRuntime(root: root)

            // Initial render
            _ = runtime.renderFrame()

            // Update scroll offset (this updates overlay geometry)
            scrollPanel.scrollOffset = 40

            // Without re-rendering, move pointer to where the updated indicator should be
            // The indicator should have moved down after scroll
            runtime.pointerMoved(to: Point(x: 83, y: 50))

            // Tick animations to apply color change
            _ = runtime.tickAnimations(at: Win32Window.currentTimestampSeconds() + 1)

            // The indicator should be hovered (using updated geometry from prepaint)
            XCTAssertEqual(
                scrollPanel.scrollIndicatorColor, hoverColor,
                "Updated overlay geometry should be interactive before render")
        }
    }

    // MARK: - VAL-PARITY-011: Minimum frame interval gates both frame and scene refresh safely

    func testMinimumFrameIntervalGatesFrameRefresh() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
            )
            let runtime = RetainedViewRuntime(root: node)
            runtime.minimumFrameInterval = 1.0 / 60.0

            // Initial frame render
            let firstFrame = runtime.renderFrame(at: 1.0)
            XCTAssertEqual(fillRectCommands(in: firstFrame).first?.color, Color(red: 1, green: 0, blue: 0, alpha: 1))
            XCTAssertFalse(runtime.isDirty)

            // Change color
            node.backgroundColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
            XCTAssertTrue(runtime.isDirty)

            // Try to render too soon - should return cached frame
            let throttledFrame = runtime.renderFrame(at: 1.005)
            XCTAssertEqual(
                fillRectCommands(in: throttledFrame).first?.color, Color(red: 1, green: 0, blue: 0, alpha: 1),
                "Should return cached (red) frame when throttled")
            XCTAssertTrue(runtime.isDirty, "Should still be dirty after throttled render")

            // Render after enough time has passed
            let refreshedFrame = runtime.renderFrame(at: 1.020)
            XCTAssertEqual(
                fillRectCommands(in: refreshedFrame).first?.color, Color(red: 0, green: 0, blue: 1, alpha: 1),
                "Should return updated (blue) frame after interval")
            XCTAssertFalse(runtime.isDirty, "Should not be dirty after successful render")
        }
    }

    func testMinimumFrameIntervalGatesSceneRefresh() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
            )
            let runtime = RetainedViewRuntime(root: node)
            runtime.minimumFrameInterval = 1.0 / 60.0

            // Initial scene render
            let firstScene = runtime.renderScene(at: 1.0)
            XCTAssertEqual(firstScene.layers[0].quads[0].startR, 1)
            XCTAssertFalse(runtime.isDirty)

            // Change color
            node.backgroundColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
            XCTAssertTrue(runtime.isDirty)

            // Try to render too soon - should return cached scene
            let throttledScene = runtime.renderScene(at: 1.005)
            XCTAssertEqual(throttledScene, firstScene, "Should return cached scene when throttled")
            XCTAssertTrue(runtime.isDirty, "Should still be dirty after throttled render")

            // Render after enough time has passed
            let refreshedScene = runtime.renderScene(at: 1.020)
            XCTAssertEqual(refreshedScene.layers[0].quads[0].startR, 0)
            XCTAssertEqual(refreshedScene.layers[0].quads[0].startB, 1)
            XCTAssertFalse(runtime.isDirty, "Should not be dirty after successful render")
        }
    }

}
private struct NormalizedOutput {
    let rects: [Rect]
    let colors: [Color]

    var normalizedRects: [NormalizedRect] {
        rects.map { NormalizedRect(rect: $0) }
    }

    var normalizedColors: [NormalizedColor] {
        colors.map { NormalizedColor(color: $0) }
    }
}
private struct NormalizedRect: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(rect: Rect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }
}
private struct NormalizedColor: Equatable {
    let r: Float
    let g: Float
    let b: Float
    let a: Float

    init(color: Color) {
        self.r = color.red
        self.g = color.green
        self.b = color.blue
        self.a = color.alpha
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
private func sceneFillRects(in scene: GPUIScene) -> [Rect] {
    scene.layers.flatMap { layer in
        layer.quads.map { quad in
            Rect(x: Double(quad.x), y: Double(quad.y), width: Double(quad.width), height: Double(quad.height))
        }
    }
}
private func sceneQuadColors(in scene: GPUIScene) -> [Color] {
    scene.layers.flatMap { layer in
        layer.quads.map { quad in
            Color(red: quad.startR, green: quad.startG, blue: quad.startB, alpha: quad.startA)
        }
    }
}
private func drawCommandRects(in frame: RenderFrame) -> [Rect] {
    frame.commands.compactMap { command in
        switch command {
        case .fillRect(let fillRect):
            return fillRect.rect
        case .drawBitmap(let drawBitmap):
            return drawBitmap.rect
        case .applyBlur, .fillPath, .strokePath, .drawText, .pushClip, .popClip:
            return nil
        }
    }
}
