import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Passive label/container nodes must not swallow interaction meant for the
/// enabled retained control that owns them.
@MainActor
final class PointerAncestorRoutingTests: XCTestCase {
    private func makeRuntime(
        children: [ViewNode],
        parentFrame: Rect = Rect(x: 10, y: 10, width: 100, height: 70),
        parentIsHitTestVisible: Bool = true
    ) -> (runtime: RetainedViewRuntime, parent: ViewNode) {
        let parent = ViewNode(
            frame: parentFrame,
            isFocusable: parentIsHitTestVisible,
            isHitTestVisible: parentIsHitTestVisible,
            children: children
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 180, height: 140),
            isHitTestVisible: false,
            children: [parent]
        )
        let runtime = RetainedViewRuntime(root: root)
        _ = runtime.renderFrame()
        return (runtime, parent)
    }

    private func makeViewRuntime<V: View>(
        _ view: V,
        size: Size = Size(width: 320, height: 180)
    ) -> (runtime: RetainedViewRuntime, node: ViewNode) {
        let root = ViewNode(frame: Rect(origin: .zero, size: size), isHitTestVisible: false)
        let runtime = RetainedViewRuntime(root: root)
        let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        node.frame = Rect(origin: .zero, size: size)
        root.addChild(node)
        _ = runtime.renderFrame()
        return (runtime, node)
    }

    private func firstNode(in node: ViewNode, where predicate: (ViewNode) -> Bool) -> ViewNode? {
        if predicate(node) {
            return node
        }
        for child in node.children {
            if let match = firstNode(in: child, where: predicate) {
                return match
            }
        }
        return nil
    }

    private func absoluteCenter(of node: ViewNode) -> Point {
        var center = Point(x: node.resolvedFrame.midX, y: node.resolvedFrame.midY)
        var ancestor = node.parent
        while let current = ancestor {
            center.x += current.resolvedFrame.origin.x
            center.y += current.resolvedFrame.origin.y
            ancestor = current.parent
        }
        return center
    }

    func testSwiftUIButtonWithHitTestableNestedLabelActivatesAtRealPointerCoordinates() async {
        await MainActor.run {
            var activations = 0
            let fixture = makeViewRuntime(
                Button {
                    activations += 1
                } label: {
                    HStack(spacing: 8) {
                        Text("Launch")
                        Text("demo")
                    }
                    .padding(6)
                    .allowsHitTesting(true)
                }
            )

            guard
                let label = firstNode(
                    in: fixture.node,
                    where: {
                        $0 !== fixture.node && $0.isHitTestVisible && $0.onActivate == nil
                    })
            else {
                return XCTFail("Expected a hit-test-visible passive Button label")
            }

            let point = absoluteCenter(of: label)
            fixture.runtime.pointerMoved(to: point)
            fixture.runtime.pointerDown(at: point)
            fixture.runtime.pointerUp(at: point)

            XCTAssertEqual(activations, 1)
            XCTAssertTrue(fixture.node.isHovered)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.node)
        }
    }

    func testSwiftUIButtonLabelOnHoverPreservesHoverCallbacksAndStillActivates() async {
        await MainActor.run {
            var activations = 0
            var hoverStates: [Bool] = []
            let fixture = makeViewRuntime(
                Button {
                    activations += 1
                } label: {
                    Text("Hover and launch")
                        .padding(6)
                        .onHover { hoverStates.append($0) }
                }
            )

            guard let label = firstNode(in: fixture.node, where: { $0.onPointerEnter != nil }) else {
                return XCTFail("Expected a Button label with its own hover callback")
            }

            let point = absoluteCenter(of: label)
            fixture.runtime.pointerMoved(to: point)
            fixture.runtime.pointerDown(at: point)

            XCTAssertEqual(fixture.runtime.interactionPhase(for: fixture.node), .pressed)

            fixture.runtime.pointerUp(at: point)

            XCTAssertEqual(activations, 1)
            XCTAssertEqual(hoverStates, [true])
            XCTAssertTrue(label.isHovered)
            XCTAssertFalse(fixture.node.isHovered)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.node)

            fixture.runtime.pointerExitedWindow()

            XCTAssertEqual(hoverStates, [true, false])
        }
    }

    func testSwiftUIButtonLabelContinuousHoverPreservesLocationsAndStillActivates() async {
        await MainActor.run {
            var activations = 0
            var hoverPhases: [HoverPhase] = []
            let fixture = makeViewRuntime(
                Button {
                    activations += 1
                } label: {
                    Text("Track and launch")
                        .padding(6)
                        .onContinuousHover { hoverPhases.append($0) }
                }
            )

            guard let label = firstNode(in: fixture.node, where: { $0.onPointerMove != nil }) else {
                return XCTFail("Expected a Button label with its own continuous-hover callback")
            }

            let point = absoluteCenter(of: label)
            let secondPoint = Point(x: point.x + 1, y: point.y)
            fixture.runtime.pointerMoved(to: point)
            fixture.runtime.pointerDown(at: point)
            fixture.runtime.pointerUp(at: point)
            fixture.runtime.pointerMoved(to: secondPoint)
            fixture.runtime.pointerExitedWindow()

            XCTAssertEqual(activations, 1)
            XCTAssertEqual(hoverPhases, [.active(point), .active(secondPoint), .ended])
        }
    }

    func testSwiftUIButtonLabelHoverEffectRemainsVisibleAndStillActivates() async {
        await MainActor.run {
            var activations = 0
            let fixture = makeViewRuntime(
                Button {
                    activations += 1
                } label: {
                    Text("Highlighted launch")
                        .padding(6)
                        .hoverEffect(.highlight)
                }
            )

            guard let label = firstNode(in: fixture.node, where: { $0.hoverEffect == .highlight }) else {
                return XCTFail("Expected a Button label with its own hover effect")
            }

            let point = absoluteCenter(of: label)
            fixture.runtime.pointerMoved(to: point)
            fixture.runtime.pointerDown(at: point)
            fixture.runtime.pointerUp(at: point)

            XCTAssertEqual(activations, 1)
            XCTAssertTrue(label.isHovered)
            XCTAssertFalse(fixture.node.isHovered)
        }
    }

    func testSwiftUIButtonRepeatStillRunsWhenItsLabelOwnsHover() async {
        await MainActor.run {
            var activations = 0
            let fixture = makeViewRuntime(
                Button {
                    activations += 1
                } label: {
                    Text("Repeat while hovering")
                        .padding(6)
                        .onHover { _ in }
                }
                .buttonRepeatBehavior(.enabled)
            )

            guard let label = firstNode(in: fixture.node, where: { $0.onPointerEnter != nil }) else {
                return XCTFail("Expected a repeating Button label with its own hover callback")
            }

            let point = absoluteCenter(of: label)
            fixture.runtime.pointerMoved(to: point)
            fixture.runtime.pointerDown(at: point)

            XCTAssertTrue(label.isHovered)
            XCTAssertFalse(fixture.node.isHovered)
            XCTAssertFalse(fixture.runtime.tickAnimations(at: 1.0))
            XCTAssertTrue(fixture.runtime.tickAnimations(at: 1.45))
            XCTAssertEqual(activations, 1)
            XCTAssertTrue(fixture.runtime.tickAnimations(at: 1.531))
            XCTAssertEqual(activations, 2)

            fixture.runtime.pointerUp(at: point)

            XCTAssertEqual(activations, 2)
        }
    }

    func testSwiftUISelectableListRowRespondsWhenItsNestedContentOwnsTheHit() async {
        await MainActor.run {
            var selected: String?
            let selection = Binding<String?>(get: { selected }, set: { selected = $0 })
            let fixture = makeViewRuntime(
                List(selection: selection) {
                    HStack(spacing: 6) {
                        Text("Select")
                        Text("this row")
                    }
                    .padding(6)
                    .allowsHitTesting(true)
                    .tag("chosen")
                }
            )

            guard let row = firstNode(in: fixture.node, where: { $0.onActivate != nil }),
                let content = firstNode(
                    in: row,
                    where: {
                        $0 !== row && $0.isHitTestVisible && $0.onActivate == nil
                    })
            else {
                return XCTFail("Expected a selectable row with hit-test-visible passive content")
            }

            let point = absoluteCenter(of: content)
            fixture.runtime.pointerMoved(to: point)
            fixture.runtime.pointerDown(at: point)
            fixture.runtime.pointerUp(at: point)

            XCTAssertEqual(selected, "chosen")
            XCTAssertTrue(row.isHovered)
            XCTAssertTrue(fixture.runtime.focusedNode === row)
        }
    }

    func testPassiveDescendantRoutesHoverPressAndActivationToOwningControl() async {
        await MainActor.run {
            let child = ViewNode(frame: Rect(x: 8, y: 8, width: 35, height: 25))
            let fixture = makeRuntime(children: [child])
            var activations = 0
            fixture.parent.onActivate = { activations += 1 }
            let point = Point(x: 24, y: 24)

            fixture.runtime.pointerMoved(to: point)

            XCTAssertTrue(fixture.parent.isHovered)
            XCTAssertFalse(child.isHovered)

            fixture.runtime.pointerDown(at: point)

            XCTAssertTrue(fixture.runtime.focusedNode === fixture.parent)
            XCTAssertEqual(fixture.runtime.interactionPhase(for: fixture.parent), .pressed)

            fixture.runtime.pointerUp(at: point)

            XCTAssertEqual(activations, 1)
            XCTAssertNotEqual(fixture.runtime.interactionPhase(for: fixture.parent), .pressed)
            XCTAssertTrue(fixture.parent.isHovered)
        }
    }

    func testDeferredPassiveDescendantActivatesOwningControl() async {
        await MainActor.run {
            let child = ViewNode(
                frame: Rect(x: 8, y: 8, width: 35, height: 25),
                paintsInDeferredPhase: true
            )
            let fixture = makeRuntime(children: [child])
            var activations = 0
            fixture.parent.onActivate = { activations += 1 }
            let point = Point(x: 24, y: 24)

            fixture.runtime.pointerMoved(to: point)
            fixture.runtime.pointerDown(at: point)
            fixture.runtime.pointerUp(at: point)

            XCTAssertTrue(fixture.parent.isHovered)
            XCTAssertEqual(activations, 1)
        }
    }

    func testReleasingOverAnotherPassiveDescendantStillActivatesOwningControl() async {
        await MainActor.run {
            let first = ViewNode(frame: Rect(x: 5, y: 8, width: 30, height: 25))
            let second = ViewNode(frame: Rect(x: 45, y: 8, width: 30, height: 25))
            let fixture = makeRuntime(children: [first, second])
            var activations = 0
            fixture.parent.onActivate = { activations += 1 }

            fixture.runtime.pointerDown(at: Point(x: 24, y: 24))
            fixture.runtime.pointerUp(at: Point(x: 64, y: 24))

            XCTAssertEqual(activations, 1)
            XCTAssertTrue(fixture.parent.isHovered)
        }
    }

    func testNestedActivatableChildRetainsItsOwnActionAndFocus() async {
        await MainActor.run {
            var childActivations = 0
            let child = ViewNode(
                frame: Rect(x: 8, y: 8, width: 35, height: 25),
                isFocusable: true
            )
            child.onActivate = { childActivations += 1 }
            let fixture = makeRuntime(children: [child])
            var parentActivations = 0
            fixture.parent.onActivate = { parentActivations += 1 }
            let point = Point(x: 24, y: 24)

            fixture.runtime.pointerMoved(to: point)
            fixture.runtime.pointerDown(at: point)
            fixture.runtime.pointerUp(at: point)

            XCTAssertEqual(childActivations, 1)
            XCTAssertEqual(parentActivations, 0)
            XCTAssertTrue(fixture.runtime.focusedNode === child)
            XCTAssertTrue(child.isHovered)
            XCTAssertFalse(fixture.parent.isHovered)
        }
    }

    func testExplicitChildPointerHandlersRemainIndependent() async {
        await MainActor.run {
            var childPresses = 0
            var childReleases = 0
            let child = ViewNode(frame: Rect(x: 8, y: 8, width: 35, height: 25))
            child.onPointerDown = { childPresses += 1 }
            child.onPointerUpInside = { childReleases += 1 }
            let fixture = makeRuntime(children: [child])
            var parentActivations = 0
            fixture.parent.onActivate = { parentActivations += 1 }
            let point = Point(x: 24, y: 24)

            fixture.runtime.pointerDown(at: point)
            fixture.runtime.pointerUp(at: point)

            XCTAssertEqual(childPresses, 1)
            XCTAssertEqual(childReleases, 1)
            XCTAssertEqual(parentActivations, 0)
        }
    }

    func testExplicitChildHoverCallbacksRemainIndependent() async {
        await MainActor.run {
            var childHoverEnters = 0
            var parentActivations = 0
            let child = ViewNode(frame: Rect(x: 8, y: 8, width: 35, height: 25))
            child.onPointerEnter = { childHoverEnters += 1 }
            let fixture = makeRuntime(children: [child])
            fixture.parent.onActivate = { parentActivations += 1 }
            let point = Point(x: 24, y: 24)

            fixture.runtime.pointerMoved(to: point)
            fixture.runtime.pointerDown(at: point)
            fixture.runtime.pointerUp(at: point)

            XCTAssertEqual(childHoverEnters, 1)
            XCTAssertEqual(parentActivations, 1)
            XCTAssertTrue(child.isHovered)
            XCTAssertFalse(fixture.parent.isHovered)
        }
    }

    func testNonHitTestableAncestorNeverReceivesDescendantActivation() async {
        await MainActor.run {
            let child = ViewNode(frame: Rect(x: 8, y: 8, width: 35, height: 25))
            let fixture = makeRuntime(children: [child], parentIsHitTestVisible: false)
            var parentActivations = 0
            fixture.parent.onActivate = { parentActivations += 1 }
            let point = Point(x: 24, y: 24)

            fixture.runtime.pointerDown(at: point)
            fixture.runtime.pointerUp(at: point)

            XCTAssertEqual(parentActivations, 0)
            XCTAssertFalse(fixture.parent.isHovered)
        }
    }

    func testReleaseOutsideOwningControlCancelsActivation() async {
        await MainActor.run {
            let child = ViewNode(frame: Rect(x: 8, y: 8, width: 35, height: 25))
            let fixture = makeRuntime(children: [child])
            var parentActivations = 0
            var outsideReleases = 0
            fixture.parent.onActivate = { parentActivations += 1 }
            fixture.parent.onPointerUpOutside = { outsideReleases += 1 }

            fixture.runtime.pointerDown(at: Point(x: 24, y: 24))
            fixture.runtime.pointerUp(at: Point(x: 150, y: 110))

            XCTAssertEqual(parentActivations, 0)
            XCTAssertEqual(outsideReleases, 1)
            XCTAssertFalse(fixture.parent.isHovered)
        }
    }

    func testDescendantOutsideAncestorInteractionBoundsDoesNotActivateIt() async {
        await MainActor.run {
            let child = ViewNode(frame: Rect(x: 45, y: 8, width: 35, height: 25))
            let fixture = makeRuntime(
                children: [child],
                parentFrame: Rect(x: 10, y: 10, width: 55, height: 70)
            )
            var parentActivations = 0
            fixture.parent.onActivate = { parentActivations += 1 }
            let outsideParentPoint = Point(x: 75, y: 24)

            fixture.runtime.pointerDown(at: outsideParentPoint)
            fixture.runtime.pointerUp(at: outsideParentPoint)

            XCTAssertEqual(parentActivations, 0)
            XCTAssertFalse(fixture.parent.isHovered)
        }
    }

    func testScrollableDescendantRemainsIndependentOfActivatableAncestor() async {
        await MainActor.run {
            let content = ViewNode(
                frame: Rect(x: 0, y: 0, width: 50, height: 180),
                isHitTestVisible: false
            )
            let child = ViewNode(
                frame: Rect(x: 8, y: 8, width: 55, height: 35),
                children: [content]
            )
            child.scrollAxis = .vertical
            let fixture = makeRuntime(children: [child])
            var parentActivations = 0
            fixture.parent.onActivate = { parentActivations += 1 }
            let point = Point(x: 24, y: 24)

            fixture.runtime.pointerDown(at: point)
            fixture.runtime.pointerUp(at: point)
            fixture.runtime.mouseWheel(at: point, delta: -1)

            XCTAssertEqual(parentActivations, 0)
            XCTAssertGreaterThan(child.scrollOffset, 0)
        }
    }

    func testScrollingOverPassiveControlContentKeepsOwningControlHovered() async {
        await MainActor.run {
            let label = ViewNode(frame: Rect(x: 8, y: 8, width: 35, height: 25))
            let button = ViewNode(
                frame: Rect(x: 10, y: 10, width: 100, height: 45),
                isFocusable: true,
                children: [label]
            )
            button.onActivate = {}
            let overflow = ViewNode(
                frame: Rect(x: 0, y: 120, width: 100, height: 80),
                isHitTestVisible: false
            )
            let scrollView = ViewNode(
                frame: Rect(x: 0, y: 0, width: 140, height: 70),
                clipsToBounds: true,
                scrollAxis: .vertical,
                children: [button, overflow]
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 180, height: 140),
                isHitTestVisible: false,
                children: [scrollView]
            )
            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()
            let point = Point(x: 30, y: 28)

            runtime.pointerMoved(to: point)
            XCTAssertTrue(button.isHovered)

            runtime.mouseWheel(at: point, delta: -0.1)

            XCTAssertGreaterThan(scrollView.scrollOffset, 0)
            XCTAssertTrue(button.isHovered)
            XCTAssertFalse(label.isHovered)
        }
    }

    func testDraggableDescendantRetainsDragGestureInsteadOfActivatingAncestor() async {
        await MainActor.run {
            var dragStarts = 0
            var dragEnds = 0
            let child = ViewNode(frame: Rect(x: 8, y: 8, width: 35, height: 25))
            child.onDragStart = { _ in dragStarts += 1 }
            child.onDragEnd = { _, _ in dragEnds += 1 }
            let fixture = makeRuntime(children: [child])
            var parentActivations = 0
            fixture.parent.onActivate = { parentActivations += 1 }

            fixture.runtime.pointerDown(at: Point(x: 24, y: 24))
            fixture.runtime.pointerMoved(to: Point(x: 34, y: 30))
            fixture.runtime.pointerUp(at: Point(x: 34, y: 30))

            XCTAssertEqual(dragStarts, 1)
            XCTAssertEqual(dragEnds, 1)
            XCTAssertEqual(parentActivations, 0)
        }
    }
}
