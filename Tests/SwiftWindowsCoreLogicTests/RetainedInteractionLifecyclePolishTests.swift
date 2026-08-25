import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedInteractionLifecyclePolishTests: XCTestCase {
    private let palette = SurfacePalette(
        idle: Color(red: 0.15, green: 0.20, blue: 0.25, alpha: 1),
        focused: Color(red: 0.25, green: 0.30, blue: 0.35, alpha: 1),
        pressed: Color(red: 0.45, green: 0.50, blue: 0.55, alpha: 1)
    )

    private func makeRuntime(size: Size = Size(width: 240, height: 180)) -> RetainedViewRuntime {
        let root = ViewNode(frame: Rect(origin: .zero, size: size), isHitTestVisible: false)
        return RetainedViewRuntime(root: root)
    }

    private func makeButton(
        runtime: RetainedViewRuntime,
        frame: Rect = Rect(x: 20, y: 20, width: 100, height: 36),
        repeatBehavior: RetainedButtonRepeatBehavior = .automatic,
        isEnabled: Bool = true,
        action: (() -> Void)? = nil
    ) -> ViewNode {
        Controls.button(
            runtime: runtime,
            frame: frame,
            cornerRadius: 6,
            palette: palette,
            isEnabled: isEnabled,
            repeatBehavior: repeatBehavior,
            animation: ControlAnimationStyle(focusDuration: 0, pressDuration: 0),
            action: action
        )
    }

    func testPointerCancellationClearsPressedChromeAndStopsButtonRepeatWithoutActivation() async {
        let runtime = makeRuntime()
        var activations = 0
        var outsideReleases = 0
        let button = makeButton(runtime: runtime, repeatBehavior: .enabled) {
            activations += 1
        }
        button.onPointerUpOutside = { outsideReleases += 1 }
        runtime.root.addChild(button)

        runtime.pointerMoved(to: Point(x: 40, y: 36))
        runtime.pointerDown(at: Point(x: 40, y: 36))

        XCTAssertEqual(runtime.interactionPhase(for: button), .pressed)
        XCTAssertTrue(button.isHovered)

        runtime.pointerCancelled()

        XCTAssertEqual(outsideReleases, 1)
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(runtime.interactionPhase(for: button), .focused)
        XCTAssertFalse(button.isHovered)
        XCTAssertTrue(runtime.focusedNode === button)

        _ = runtime.tickAnimations(at: 1)
        _ = runtime.tickAnimations(at: 2)
        runtime.pointerUp(at: Point(x: 40, y: 36))

        XCTAssertEqual(activations, 0)
        XCTAssertEqual(outsideReleases, 1)
    }

    func testPointerCancellationIsIdempotentForAnActivePress() async {
        let runtime = makeRuntime()
        var outsideReleases = 0
        let button = makeButton(runtime: runtime)
        button.onPointerUpOutside = { outsideReleases += 1 }
        runtime.root.addChild(button)

        runtime.pointerDown(at: Point(x: 40, y: 36))
        runtime.pointerCancelled()
        runtime.pointerCancelled()

        XCTAssertEqual(outsideReleases, 1)
        XCTAssertFalse(button.isHovered)
        XCTAssertEqual(runtime.interactionPhase(for: button), .focused)
    }

    func testPointerCancellationEndsDragAtItsLastDeliveredPointerLocation() async {
        let runtime = makeRuntime()
        let handle = ViewNode(frame: Rect(x: 20, y: 20, width: 120, height: 40))
        var dragChanges = 0
        var dragEndPoints: [Point] = []
        var dragEndDeltas: [Point] = []
        handle.onDragStart = { _ in }
        handle.onDragChange = { _, _ in dragChanges += 1 }
        handle.onDragEnd = { point, delta in
            dragEndPoints.append(point)
            dragEndDeltas.append(delta)
        }
        runtime.root.addChild(handle)

        runtime.pointerDown(at: Point(x: 30, y: 30))
        runtime.pointerMoved(to: Point(x: 76, y: 43))
        runtime.pointerCancelled()
        runtime.pointerMoved(to: Point(x: 95, y: 50))
        runtime.pointerUp(at: Point(x: 95, y: 50))

        XCTAssertEqual(dragChanges, 1)
        XCTAssertEqual(dragEndPoints, [Point(x: 76, y: 43)])
        XCTAssertEqual(dragEndDeltas, [Point(x: 46, y: 13)])
    }

    func testPointerCancellationEndsSliderEditingAndStopsFurtherValueChanges() async {
        let runtime = makeRuntime()
        var editingChanges: [Bool] = []
        var values: [Double] = []
        let slider = Controls.slider(
            runtime: runtime,
            value: 0.25,
            preferredSize: Size(width: 180, height: 28),
            onValueChanged: { values.append($0) },
            onEditingChanged: { editingChanges.append($0) }
        )
        slider.frame = Rect(x: 20, y: 20, width: 180, height: 28)
        runtime.root.addChild(slider)

        runtime.pointerDown(at: Point(x: 40, y: 34))
        runtime.pointerMoved(to: Point(x: 80, y: 34))
        runtime.pointerCancelled()
        let valuesAtCancellation = values

        runtime.pointerMoved(to: Point(x: 140, y: 34))
        runtime.pointerCancelled()
        runtime.pointerUp(at: Point(x: 140, y: 34))

        XCTAssertEqual(editingChanges, [true, false])
        XCTAssertEqual(values, valuesAtCancellation)
        XCTAssertEqual(values.count, 1)
        XCTAssertTrue(runtime.focusedNode === slider)
    }

    func testPointerCancellationEndsScrollIndicatorDragAndRestoresIdleChrome() async {
        let idleColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 0.3)
        let hoverColor = Color(red: 0.9, green: 0.95, blue: 1, alpha: 0.55)
        let activeColor = Color(red: 1, green: 1, blue: 1, alpha: 0.8)
        let items = (0..<4).map { _ in
            ViewNode(preferredSize: Size(width: 60, height: 30))
        }
        let scroller = ViewNode(
            frame: Rect(x: 10, y: 10, width: 80, height: 70),
            layoutMode: .stack(
                .vertical(spacing: 10, padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            ),
            scrollAxis: .vertical,
            showsScrollIndicator: true,
            scrollIndicatorColor: idleColor,
            scrollIndicatorHoverColor: hoverColor,
            scrollIndicatorActiveColor: activeColor,
            isHitTestVisible: false,
            children: items
        )
        let runtime = makeRuntime(size: Size(width: 120, height: 120))
        runtime.clock = { 1 }
        runtime.root.addChild(scroller)
        _ = runtime.renderFrame()

        runtime.pointerMoved(to: Point(x: 79, y: 18))
        runtime.pointerDown(at: Point(x: 79, y: 18))
        _ = runtime.tickAnimations(at: 2)
        XCTAssertEqual(scroller.scrollIndicatorColor, activeColor)

        runtime.pointerMoved(to: Point(x: 79, y: 38))
        let offsetAtCancellation = scroller.scrollOffset
        XCTAssertGreaterThan(offsetAtCancellation, 0)

        runtime.pointerCancelled()
        _ = runtime.tickAnimations(at: 2)
        runtime.pointerMoved(to: Point(x: 40, y: 65))

        XCTAssertEqual(scroller.scrollIndicatorColor, idleColor)
        XCTAssertEqual(scroller.scrollOffset, offsetAtCancellation)
    }

    func testContextClickOnPassiveLabelPreservesOwningButtonHover() async {
        let runtime = makeRuntime()
        let label = ViewNode(frame: Rect(x: 8, y: 8, width: 52, height: 20))
        let button = ViewNode(
            frame: Rect(x: 20, y: 20, width: 100, height: 40),
            isFocusable: true,
            children: [label]
        )
        var contextPoints: [Point] = []
        button.onActivate = {}
        button.onContextMenu = { contextPoints.append($0) }
        runtime.root.addChild(button)

        let point = Point(x: 36, y: 36)
        runtime.pointerMoved(to: point)
        runtime.contextClick(at: point)

        XCTAssertTrue(button.isHovered)
        XCTAssertFalse(label.isHovered)
        XCTAssertEqual(contextPoints, [point])
    }

    func testContextClickPreservesExplicitLabelHoverAndAncestorContextMenu() async {
        let runtime = makeRuntime()
        let label = ViewNode(frame: Rect(x: 8, y: 8, width: 52, height: 20))
        let button = ViewNode(
            frame: Rect(x: 20, y: 20, width: 100, height: 40),
            isFocusable: true,
            children: [label]
        )
        var hoverEntries = 0
        var contextCount = 0
        label.onPointerEnter = { hoverEntries += 1 }
        button.onActivate = {}
        button.onContextMenu = { _ in contextCount += 1 }
        runtime.root.addChild(button)

        let point = Point(x: 36, y: 36)
        runtime.pointerMoved(to: point)
        runtime.contextClick(at: point)

        XCTAssertEqual(hoverEntries, 1)
        XCTAssertTrue(label.isHovered)
        XCTAssertFalse(button.isHovered)
        XCTAssertEqual(contextCount, 1)
    }

    func testRemovingFocusedSubtreeClearsFocusAndStopsDetachedKeyboardActivation() async {
        let runtime = makeRuntime()
        let focused = ViewNode(frame: Rect(x: 6, y: 6, width: 80, height: 30), isFocusable: true)
        let container = ViewNode(frame: Rect(x: 20, y: 20, width: 120, height: 50), children: [focused])
        var focusExits = 0
        var activations = 0
        var reportedFocus: [Bool] = []
        focused.onFocusExit = { focusExits += 1 }
        focused.onActivate = { activations += 1 }
        runtime.onAccessibilityFocusChanged = { reportedFocus.append($0 != nil) }
        runtime.root.addChild(container)
        runtime.requestFocus(focused)

        container.removeFromParent()
        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

        XCTAssertNil(runtime.focusedNode)
        XCTAssertFalse(focused.isFocused)
        XCTAssertEqual(focusExits, 1)
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(reportedFocus, [true, false])
    }

    func testHidingAncestorClearsDescendantFocusAndHover() async {
        let runtime = makeRuntime()
        let focused = ViewNode(frame: Rect(x: 6, y: 6, width: 80, height: 30), isFocusable: true)
        let container = ViewNode(frame: Rect(x: 20, y: 20, width: 120, height: 50), children: [focused])
        var focusExits = 0
        focused.onFocusExit = { focusExits += 1 }
        runtime.root.addChild(container)
        runtime.pointerMoved(to: Point(x: 40, y: 35))
        runtime.requestFocus(focused)

        XCTAssertTrue(focused.isHovered)

        container.isHidden = true

        XCTAssertNil(runtime.focusedNode)
        XCTAssertFalse(focused.isFocused)
        XCTAssertFalse(focused.isHovered)
        XCTAssertEqual(focusExits, 1)
    }

    func testBecomingNonFocusableImmediatelyReleasesExistingFocus() async {
        let runtime = makeRuntime()
        let focused = ViewNode(frame: Rect(x: 20, y: 20, width: 80, height: 30), isFocusable: true)
        var focusExits = 0
        focused.onFocusExit = { focusExits += 1 }
        runtime.root.addChild(focused)
        runtime.requestFocus(focused)

        focused.isFocusable = false

        XCTAssertNil(runtime.focusedNode)
        XCTAssertFalse(focused.isFocused)
        XCTAssertEqual(focusExits, 1)
    }

    func testFocusRequestRejectsHiddenNodeAndHiddenAncestor() async {
        let runtime = makeRuntime()
        let hidden = ViewNode(
            frame: Rect(x: 20, y: 20, width: 80, height: 30),
            isFocusable: true,
            isHidden: true
        )
        let nested = ViewNode(frame: Rect(x: 4, y: 4, width: 60, height: 24), isFocusable: true)
        let hiddenParent = ViewNode(
            frame: Rect(x: 20, y: 70, width: 80, height: 35),
            isHidden: true,
            children: [nested]
        )
        runtime.root.addChild(hidden)
        runtime.root.addChild(hiddenParent)

        runtime.requestFocus(hidden)
        XCTAssertNil(runtime.focusedNode)

        runtime.requestFocus(nested)
        XCTAssertNil(runtime.focusedNode)

        hiddenParent.isHidden = false
        runtime.requestFocus(nested)
        XCTAssertTrue(runtime.focusedNode === nested)
    }

    func testRemovingPressedButtonCancelsItsRepeatAndClearsFocus() async {
        let runtime = makeRuntime()
        var activations = 0
        var outsideReleases = 0
        let button = makeButton(runtime: runtime, repeatBehavior: .enabled) {
            activations += 1
        }
        button.onPointerUpOutside = { outsideReleases += 1 }
        runtime.root.addChild(button)
        runtime.pointerDown(at: Point(x: 40, y: 36))

        button.removeFromParent()
        _ = runtime.tickAnimations(at: 1)
        _ = runtime.tickAnimations(at: 2)
        runtime.pointerUp(at: Point(x: 40, y: 36))

        XCTAssertNil(runtime.focusedNode)
        XCTAssertFalse(button.isFocused)
        XCTAssertFalse(button.isHovered)
        XCTAssertEqual(outsideReleases, 1)
        XCTAssertEqual(activations, 0)
    }

    func testDisabledRetainedButtonsTogglesAndSlidersProjectAsDisabled() async {
        let runtime = makeRuntime()
        let button = makeButton(runtime: runtime, isEnabled: false)
        let toggle = Controls.toggle(runtime: runtime, isOn: true, isEnabled: false)
        let slider = Controls.slider(runtime: runtime, value: 0.5, isEnabled: false)

        XCTAssertEqual(AccessibilityProjection.project(root: button)?.isEnabled, false)
        XCTAssertEqual(AccessibilityProjection.project(root: toggle)?.isEnabled, false)
        XCTAssertEqual(AccessibilityProjection.project(root: slider)?.isEnabled, false)
        XCTAssertFalse(button.isHitTestVisible)
        XCTAssertFalse(toggle.isHitTestVisible)
        XCTAssertFalse(slider.isHitTestVisible)
    }

    func testDisabledSliderDoesNotSwallowPointerHitsForInteractiveContentBehindIt() async {
        let runtime = makeRuntime()
        var activations = 0
        let button = makeButton(
            runtime: runtime,
            frame: Rect(x: 20, y: 20, width: 180, height: 28)
        ) {
            activations += 1
        }
        let slider = Controls.slider(
            runtime: runtime,
            value: 0.5,
            isEnabled: false,
            preferredSize: Size(width: 180, height: 28)
        )
        slider.frame = Rect(x: 20, y: 20, width: 180, height: 28)
        runtime.root.addChild(button)
        runtime.root.addChild(slider)

        let point = Point(x: 80, y: 34)
        runtime.pointerDown(at: point)
        runtime.pointerUp(at: point)

        XCTAssertEqual(activations, 1)
        XCTAssertTrue(runtime.focusedNode === button)
    }
}
