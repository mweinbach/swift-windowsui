import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Drag gestures remain pointer presses: their focus, accessibility, and
/// post-release hover must follow the same retained routing as other controls.
@MainActor
final class DraggableFocusRoutingTests: XCTestCase {
    private func makeRuntime() -> RetainedViewRuntime {
        RetainedViewRuntime(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 360, height: 220),
                isHitTestVisible: false
            )
        )
    }

    private func attach(_ node: ViewNode, to runtime: RetainedViewRuntime) {
        runtime.root.addChild(node)
        _ = runtime.renderFrame()
    }

    private func firstNode(
        in root: ViewNode,
        matching predicate: (ViewNode) -> Bool
    ) -> ViewNode? {
        var pending = [root]
        while let node = pending.popLast() {
            if predicate(node) {
                return node
            }
            pending.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    private func absoluteCenter(of node: ViewNode) -> Point {
        var point = Point(x: node.resolvedFrame.midX, y: node.resolvedFrame.midY)
        var ancestor = node.parent
        while let current = ancestor {
            point.x += current.resolvedFrame.origin.x
            point.y += current.resolvedFrame.origin.y
            ancestor = current.parent
        }
        return point
    }

    func testRetainedSliderAcquiresFocusBeforeEditingBegins() async {
        await MainActor.run {
            let runtime = makeRuntime()
            var editingStates: [Bool] = []
            var wasFocusedWhenEditingBegan = false

            let slider = Controls.slider(
                runtime: runtime,
                value: 0.35,
                preferredSize: Size(width: 200, height: 28),
                onEditingChanged: { isEditing in
                    editingStates.append(isEditing)
                    if isEditing {
                        wasFocusedWhenEditingBegan =
                            runtime.focusedNode?.accessibilityPrefersSliderBehavior == true
                    }
                }
            )
            slider.frame = Rect(x: 20, y: 30, width: 200, height: 28)
            attach(slider, to: runtime)

            let point = absoluteCenter(of: slider)
            runtime.pointerDown(at: point)

            XCTAssertTrue(runtime.focusedNode === slider)
            XCTAssertTrue(slider.isFocused)
            XCTAssertTrue(wasFocusedWhenEditingBegan)
            XCTAssertEqual(runtime.interactionPhase(for: slider), .focused)
            XCTAssertEqual(editingStates, [true])

            _ = runtime.tickAnimations(at: 1_000_000_000_000)
            XCTAssertGreaterThan(slider.outlineWidth, 0)
            XCTAssertGreaterThan(slider.outlineColor.alpha, 0)

            runtime.pointerUp(at: point)
            XCTAssertEqual(editingStates, [true, false])
            XCTAssertTrue(runtime.focusedNode === slider)
        }
    }

    func testSwiftUISliderReceivesPointerFocusAndUpdatesItsBinding() async {
        await MainActor.run {
            let runtime = makeRuntime()
            var value = 0.25
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 360, height: 220) },
                invalidateHandler: {}
            )
            let component = Slider(
                value: Binding(get: { value }, set: { value = $0 }),
                in: 0...1
            ).makeComponent(context: context)
            let viewNode = component.makeNode(runtime: runtime)
            viewNode.frame = Rect(x: 20, y: 30, width: 220, height: 30)
            attach(viewNode, to: runtime)

            guard
                let slider = firstNode(
                    in: viewNode,
                    matching: {
                        $0.accessibilityPrefersSliderBehavior == true && $0.isFocusable
                    }
                )
            else {
                return XCTFail("Expected a real SwiftUI Slider to build a focusable retained slider")
            }

            let start = absoluteCenter(of: slider)
            runtime.pointerDown(at: start)
            XCTAssertTrue(runtime.focusedNode === slider)

            let end = Point(x: start.x + 24, y: start.y)
            runtime.pointerMoved(to: end)
            runtime.pointerUp(at: end)

            XCTAssertGreaterThan(value, 0.25)
            XCTAssertTrue(runtime.focusedNode === slider)
        }
    }

    func testDraggingSliderTransfersExistingFocusAndAccessibilityFocus() async {
        await MainActor.run {
            let runtime = makeRuntime()
            var focusEvents: [String] = []
            var accessibilityFocus: [String] = []

            let previous = ViewNode(
                frame: Rect(x: 20, y: 15, width: 120, height: 28),
                isFocusable: true,
                accessibilityLabel: "Previous field"
            )
            previous.onFocusExit = { focusEvents.append("previous-exit") }
            attach(previous, to: runtime)
            runtime.requestFocus(previous)

            let slider = Controls.slider(
                runtime: runtime,
                value: 0.5,
                preferredSize: Size(width: 180, height: 28),
                onEditingChanged: { isEditing in
                    if isEditing {
                        focusEvents.append("editing-start")
                    }
                }
            )
            slider.frame = Rect(x: 20, y: 70, width: 180, height: 28)
            slider.accessibilityLabel = "Font scale"
            slider.onFocusEnter = { focusEvents.append("slider-enter") }
            attach(slider, to: runtime)

            runtime.onAccessibilityFocusChanged = { node in
                accessibilityFocus.append(node?.accessibilityLabel ?? "none")
            }
            runtime.pointerDown(at: absoluteCenter(of: slider))

            XCTAssertFalse(previous.isFocused)
            XCTAssertTrue(slider.isFocused)
            XCTAssertTrue(runtime.focusedNode === slider)
            XCTAssertEqual(focusEvents, ["previous-exit", "slider-enter", "editing-start"])
            XCTAssertEqual(accessibilityFocus, ["Font scale"])
        }
    }

    func testDeferredPassiveDescendantFocusesItsDraggableAncestor() async {
        await MainActor.run {
            let child = ViewNode(
                frame: Rect(x: 8, y: 8, width: 40, height: 22),
                paintsInDeferredPhase: true
            )
            let owner = ViewNode(
                frame: Rect(x: 20, y: 30, width: 100, height: 50),
                isFocusable: true,
                children: [child]
            )
            let runtime = makeRuntime()
            var ownerWasFocusedAtDragStart = false
            owner.onDragStart = { _ in
                ownerWasFocusedAtDragStart = runtime.focusedNode === owner
            }
            attach(owner, to: runtime)

            runtime.pointerDown(at: Point(x: 35, y: 45))

            XCTAssertTrue(ownerWasFocusedAtDragStart)
            XCTAssertTrue(runtime.focusedNode === owner)
        }
    }

    func testDraggingANonfocusableHandleClearsThePreviousControlFocus() async {
        await MainActor.run {
            let focused = ViewNode(
                frame: Rect(x: 10, y: 10, width: 100, height: 28),
                isFocusable: true
            )
            let handle = ViewNode(frame: Rect(x: 20, y: 70, width: 24, height: 24))
            let runtime = makeRuntime()
            var wasUnfocusedAtDragStart = false
            handle.onDragStart = { _ in
                wasUnfocusedAtDragStart = runtime.focusedNode == nil
            }
            attach(focused, to: runtime)
            attach(handle, to: runtime)
            runtime.requestFocus(focused)

            runtime.pointerDown(at: Point(x: 30, y: 80))

            XCTAssertTrue(wasUnfocusedAtDragStart)
            XCTAssertNil(runtime.focusedNode)
            XCTAssertFalse(focused.isFocused)
        }
    }

    func testReleasingDragOverPassiveButtonLabelRestoresOwningButtonHover() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let slider = Controls.slider(
                runtime: runtime,
                value: 0.5,
                preferredSize: Size(width: 180, height: 28)
            )
            slider.frame = Rect(x: 20, y: 20, width: 180, height: 28)

            let label = ViewNode(frame: Rect(x: 8, y: 8, width: 55, height: 20))
            let button = ViewNode(
                frame: Rect(x: 20, y: 85, width: 120, height: 40),
                isFocusable: true,
                children: [label]
            )
            var buttonActivations = 0
            button.onActivate = { buttonActivations += 1 }

            attach(slider, to: runtime)
            attach(button, to: runtime)

            let start = absoluteCenter(of: slider)
            let end = absoluteCenter(of: label)
            runtime.pointerDown(at: start)
            runtime.pointerMoved(to: end)
            runtime.pointerUp(at: end)

            XCTAssertTrue(button.isHovered)
            XCTAssertFalse(label.isHovered)
            XCTAssertEqual(buttonActivations, 0)
            XCTAssertTrue(runtime.focusedNode === slider)
        }
    }

    func testReleasingDragOverExplicitChildHoverKeepsTheChildCallback() async {
        await MainActor.run {
            let runtime = makeRuntime()
            let slider = Controls.slider(
                runtime: runtime,
                value: 0.5,
                preferredSize: Size(width: 180, height: 28)
            )
            slider.frame = Rect(x: 20, y: 20, width: 180, height: 28)

            let label = ViewNode(frame: Rect(x: 8, y: 8, width: 55, height: 20))
            var hoverEnters = 0
            label.onPointerEnter = { hoverEnters += 1 }
            let button = ViewNode(
                frame: Rect(x: 20, y: 85, width: 120, height: 40),
                isFocusable: true,
                children: [label]
            )
            button.onActivate = {}

            attach(slider, to: runtime)
            attach(button, to: runtime)

            runtime.pointerDown(at: absoluteCenter(of: slider))
            runtime.pointerUp(at: absoluteCenter(of: label))

            XCTAssertEqual(hoverEnters, 1)
            XCTAssertTrue(label.isHovered)
            XCTAssertFalse(button.isHovered)
        }
    }
}
