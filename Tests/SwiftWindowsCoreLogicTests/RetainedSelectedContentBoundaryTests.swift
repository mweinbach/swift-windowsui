import CUIAInterop
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Regression contract for the explicitly typed structural boundary only.
/// The factory does not confer declaration, adoption, or task authority.
@MainActor
final class RetainedSelectedContentBoundaryTests: XCTestCase {
    func testTypedDetachedBoundaryKeepsItsActualChildAndStopsAtAnOrdinaryPanel() async throws {
        let selected = ViewNode(preferredSize: Size(width: 25, height: 12))
        let identity = RetainedViewIdentity(segments: [.slot(7)])
        selected.retainedViewIdentity = identity
        selected.nodeTag = "selected"
        var layouts = 0
        selected.onLayout = { _ in layouts += 1 }
        let boundary = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)

        guard case .viewThatFits? = boundary.selectedContentRole else {
            return XCTFail("Only the explicit factory creates the selected-content role")
        }
        XCTAssertEqual(boundary.children.count, 1)
        XCTAssertTrue(boundary.children.first === selected)
        XCTAssertTrue(selected.parent === boundary)
        XCTAssertNil(boundary.parent)
        XCTAssertEqual(selected.retainedViewIdentity, identity)
        XCTAssertEqual(selected.nodeTag, "selected")
        XCTAssertEqual(boundary.intrinsicContentSize(), Size(width: 25, height: 12))
        XCTAssertEqual(layouts, 0, "Detached measurement does not run layout or require adoption")
        XCTAssertNil(boundary.onLayout)
        XCTAssertNil(boundary.onAppear)
        XCTAssertNil(boundary.onActivate)

        // A real, single-child panel must remain an ordinary semantic node.
        let leaf = ViewNode(frame: Rect(x: 3, y: 4, width: 11, height: 7), backgroundColor: .white)
        let panel = ViewNode(frame: Rect(x: 7, y: 11, width: 50, height: 40), children: [leaf])
        var panelLayouts: [Rect] = []
        panel.onLayout = { panelLayouts.append($0) }
        let typed = ViewNode.selectedContentBoundary(role: .viewThatFits, child: panel)
        let runtime = makeBoundaryRuntime(operand: typed, size: IntSize(width: 100, height: 80))
        defer { retireBoundaryRuntime(runtime) }
        _ = runtime.renderFrame()

        XCTAssertNil(panel.selectedContentRole)
        XCTAssertNil(leaf.selectedContentRole)
        XCTAssertTrue(typed.children.first === panel)
        XCTAssertTrue(panel.parent === typed)
        XCTAssertTrue(leaf.parent === panel)
        XCTAssertEqual(panel.resolvedFrame, Rect(x: 7, y: 11, width: 50, height: 40))
        XCTAssertEqual(leaf.resolvedFrame, Rect(x: 3, y: 4, width: 11, height: 7))
        XCTAssertEqual(runtime.resolvedLayoutFrame(of: leaf), Rect(x: 10, y: 15, width: 11, height: 7))
        XCTAssertEqual(panelLayouts, [Rect(x: 7, y: 11, width: 50, height: 40)])
    }

    func testIntrinsicAndAbsoluteProposalsKeepTheSelectedNodesSizingRules() async {
        for depth in [0, 1, 2] {
            let greedy = ViewNode(preferredSize: Size(width: 200, height: 28))
            greedy.layoutFillAxes = .both
            let greedyOperand = wrapBoundary(greedy, depth: depth)
            XCTAssertEqual(greedyOperand.intrinsicContentSize(), Size(width: 200, height: 28))
            XCTAssertEqual(greedy.preferredSize, Size(width: 200, height: 28))
            XCTAssertEqual(greedy.frame, .zero)

            let finiteGreedy = ViewNode(preferredSize: Size(width: 200, height: 28))
            finiteGreedy.layoutFillAxes = .both
            let finiteParent = ViewNode(
                layoutConstraints: LayoutConstraints(maxWidth: 340, maxHeight: 80),
                children: [wrapBoundary(finiteGreedy, depth: depth)])
            XCTAssertEqual(finiteParent.intrinsicContentSize(), Size(width: 340, height: 80))
            XCTAssertEqual(finiteGreedy.preferredSize, Size(width: 200, height: 28))
            XCTAssertEqual(finiteGreedy.frame, .zero)

            let ideal = ViewNode(preferredSize: Size(width: 280, height: 90))
            let origin = ViewNode(
                frame: Rect(x: 30, y: 10, width: 0, height: 0),
                preferredSize: Size(width: 280, height: 90))
            let minimum = ViewNode(
                preferredSize: Size(width: 280, height: 90),
                layoutConstraints: LayoutConstraints(minWidth: 260, minHeight: 80))
            let maximum = ViewNode(
                preferredSize: Size(width: 280, height: 90),
                layoutConstraints: LayoutConstraints(maxWidth: 180, maxHeight: 40))
            let fixedWidth = ViewNode(preferredSize: Size(width: 280, height: 90))
            fixedWidth.fixedPreferredSizeAxes = .horizontalOnly
            let cases: [(ViewNode, Rect)] = [
                (ideal, Rect(x: 0, y: 0, width: 220, height: 60)),
                (origin, Rect(x: 30, y: 10, width: 190, height: 50)),
                (minimum, Rect(x: 0, y: 0, width: 260, height: 80)),
                (maximum, Rect(x: 0, y: 0, width: 180, height: 40)),
                (fixedWidth, Rect(x: 0, y: 0, width: 280, height: 60)),
            ]
            for (selected, expected) in cases {
                let authoredFrame = selected.frame
                let preference = selected.preferredSize
                let operand = wrapBoundary(selected, depth: depth)
                let runtime = makeBoundaryRuntime(operand: operand, size: IntSize(width: 220, height: 60))
                _ = runtime.renderFrame()
                XCTAssertEqual(selected.resolvedFrame, expected, "boundary depth \(depth)")
                XCTAssertEqual(runtime.resolvedLayoutFrame(of: selected), expected)
                XCTAssertEqual(selected.frame, authoredFrame)
                XCTAssertEqual(selected.preferredSize, preference)
                assertZeroOriginBoundaryPath(operand, endingAt: selected)
                retireBoundaryRuntime(runtime)
            }
        }
    }

    func testParentPriorityAndFillReadTheSelectedOperand() async {
        for depth in [0, 1, 2] {
            let first = ViewNode(backgroundColor: .white, preferredSize: Size(width: 20, height: 20))
            let selected = ViewNode(
                backgroundColor: .black, preferredSize: Size(width: 20, height: 20), layoutPriority: 1)
            let third = ViewNode(backgroundColor: .white, preferredSize: Size(width: 20, height: 20))
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 40),
                layoutMode: .stack(.horizontal(spacing: 10, alignment: .center)),
                isHitTestVisible: false, children: [first, wrapBoundary(selected, depth: depth), third])
            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()
            XCTAssertEqual(first.resolvedFrame, Rect(x: 0, y: 10, width: 20, height: 20))
            XCTAssertEqual(selected.resolvedFrame, Rect(x: 30, y: 10, width: 60, height: 20))
            XCTAssertEqual(third.resolvedFrame, Rect(x: 100, y: 10, width: 20, height: 20))
            retireBoundaryRuntime(runtime)

            let lowerPriority = ViewNode(preferredSize: Size(width: 50, height: 20))
            let higherPriority = ViewNode(preferredSize: Size(width: 50, height: 20), layoutPriority: 1)
            let shrinkRuntime = RetainedViewRuntime(
                root: ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 40),
                    layoutMode: .stack(.horizontal(spacing: 10, alignment: .center)),
                    children: [lowerPriority, wrapBoundary(higherPriority, depth: depth)]))
            _ = shrinkRuntime.renderFrame()
            XCTAssertEqual(lowerPriority.resolvedFrame, Rect(x: 0, y: 10, width: 40, height: 20))
            XCTAssertEqual(higherPriority.resolvedFrame, Rect(x: 50, y: 10, width: 50, height: 20))
            retireBoundaryRuntime(shrinkRuntime)

            let header = ViewNode(preferredSize: Size(width: 0, height: 40))
            let body = ViewNode(backgroundColor: .white)
            body.layoutFillAxes = .both
            let fillRuntime = RetainedViewRuntime(
                root: ViewNode(
                    frame: Rect(x: 0, y: 0, width: 400, height: 300),
                    layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)),
                    children: [header, wrapBoundary(body, depth: depth)]))
            _ = fillRuntime.renderFrame()
            XCTAssertEqual(header.resolvedFrame.size.height, 40, accuracy: 0.001)
            XCTAssertEqual(body.resolvedFrame, Rect(x: 0, y: 40, width: 400, height: 260))
            retireBoundaryRuntime(fillRuntime)
        }
    }

    func testMovedSlotsInvalidateLayoutWithoutApplyingPositionTwice() async {
        for depth in [0, 1, 2] {
            let selected = ViewNode(backgroundColor: .white, preferredSize: Size(width: 40, height: 20))
            selected.position = Point(x: 70, y: 30)
            var layouts: [Rect] = []
            selected.onLayout = { layouts.append($0) }
            let operand = wrapBoundary(selected, depth: depth)
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 80),
                layoutMode: .stack(.vertical(spacing: 8, alignment: .center)), children: [operand])
            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()
            XCTAssertEqual(layouts, [Rect(x: 40, y: 0, width: 40, height: 20)])
            XCTAssertEqual(selected.resolvedFrame, Rect(x: 50, y: 20, width: 40, height: 20))

            root.frame.size.height = 120
            _ = runtime.renderFrame()
            XCTAssertEqual(layouts.count, 1, "A same-slot parent relayout keeps the child's cache")
            XCTAssertGreaterThan(runtime.lastMeasureReuseCount, 0)

            root.frame.size.width = 200
            _ = runtime.renderFrame()
            XCTAssertEqual(
                layouts,
                [
                    Rect(x: 40, y: 0, width: 40, height: 20),
                    Rect(x: 80, y: 0, width: 40, height: 20),
                ])
            XCTAssertEqual(selected.resolvedFrame, Rect(x: 50, y: 20, width: 40, height: 20))

            selected.position = Point(x: 90, y: 40)
            let frame = runtime.renderFrame()
            let expected = Rect(x: 70, y: 30, width: 40, height: 20)
            XCTAssertEqual(layouts.count, 3)
            XCTAssertEqual(layouts.last, Rect(x: 80, y: 0, width: 40, height: 20))
            XCTAssertEqual(selected.resolvedFrame, expected)
            XCTAssertEqual(runtime.resolvedLayoutFrame(of: selected), expected)
            XCTAssertEqual(boundaryFills(frame).filter { $0.color == .white }.map(\.rect), [expected])
            let scene = runtime.renderScene()
            let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 200, height: 120))
            XCTAssertEqual(bitmap.pixelColor(atX: 75, y: 35), .white)
            XCTAssertEqual(bitmap.pixelColor(atX: 55, y: 25), .black)
            XCTAssertEqual(layouts.count, 3)
            XCTAssertTrue(runtime.dirtyFlags.isEmpty)
            assertZeroOriginBoundaryPath(operand, endingAt: selected)
            retireBoundaryRuntime(runtime)
        }
    }

    func testBothPaintPathsAndHitOrderReachASelectedChildInsideAnOffsetClip() async {
        for depth in [0, 1, 2] {
            for sceneFirst in [false, true] {
                var frontPresses = 0
                var backPresses = 0
                var appearances = 0
                let front = ViewNode(
                    frame: Rect(x: 10, y: 5, width: 20, height: 20), backgroundColor: .white, zIndex: 1)
                front.onPointerDown = { frontPresses += 1 }
                front.onAppear = { appearances += 1 }
                let back = ViewNode(frame: Rect(x: 10, y: 5, width: 20, height: 20), backgroundColor: .black)
                back.onPointerDown = { backPresses += 1 }
                let clip = ViewNode(
                    frame: Rect(x: 40, y: 10, width: 60, height: 40), clipsToBounds: true,
                    children: [wrapBoundary(front, depth: depth), back])
                let runtime = makeBoundaryRuntime(operand: clip, size: IntSize(width: 120, height: 80))
                if sceneFirst { _ = runtime.renderScene() } else { _ = runtime.renderFrame() }
                let frame = runtime.renderFrame()
                let scene = runtime.renderScene()
                XCTAssertEqual(
                    boundaryFills(frame).filter { $0.color == .white }.map(\.rect),
                    [Rect(x: 50, y: 15, width: 20, height: 20)])
                XCTAssertEqual(boundaryFills(frame).last?.color, .white)
                let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 120, height: 80))
                XCTAssertEqual(bitmap.pixelColor(atX: 55, y: 20), .white)
                XCTAssertEqual(bitmap.pixelColor(atX: 20, y: 20), .black)
                XCTAssertEqual(appearances, 1)
                runtime.pointerDown(at: Point(x: 55, y: 20))
                runtime.pointerUp(at: Point(x: 55, y: 20))
                XCTAssertEqual(frontPresses, 1)
                XCTAssertEqual(backPresses, 0)
                XCTAssertEqual(appearances, 1)
                retireBoundaryRuntime(runtime)
            }
        }
    }

    func testViewportResumeUsesSelectedPlacementThroughCleanBoundaries() async {
        for depth in [0, 1, 2] {
            let rows = (0..<40).map { _ in
                ViewNode(backgroundColor: .white, preferredSize: Size(width: 100, height: 20))
            }
            let physicalRows = rows.map { wrapBoundary($0, depth: depth) }
            let scroller = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40), clipsToBounds: true,
                layoutMode: .lazyStack(.vertical(spacing: 0)), scrollAxis: .vertical, children: physicalRows)
            let runtime = makeBoundaryRuntime(operand: scroller, size: IntSize(width: 200, height: 120))
            var appearances = 0
            rows[20].onAppear = { appearances += 1 }
            _ = runtime.renderScene()
            XCTAssertTrue(physicalRows[20].isLayoutDeferredByVirtualization)
            XCTAssertFalse(rows[20].hasAppeared)
            XCTAssertEqual(appearances, 0)
            XCTAssertGreaterThan(runtime.virtualizedLayoutSkipCount, 0)

            scroller.scrollOffset = 400
            _ = runtime.renderScene()
            XCTAssertFalse(physicalRows[20].isLayoutDeferredByVirtualization)
            XCTAssertEqual(rows[20].resolvedFrame, Rect(x: 0, y: 400, width: 100, height: 20))
            XCTAssertTrue(rows[20].hasAppeared)
            XCTAssertEqual(appearances, 1)
            scroller.scrollOffset = 0
            _ = runtime.renderFrame()
            scroller.scrollOffset = 400
            _ = runtime.renderScene()
            XCTAssertEqual(appearances, 1, "Viewport movement does not retire the selected occurrence")
            XCTAssertEqual(rows[20].resolvedFrame, Rect(x: 0, y: 400, width: 100, height: 20))
            retireBoundaryRuntime(runtime)
        }
    }

    func testRootButtonOwnsPointerFocusAndUIAZeroAcrossRootSizeChanges() async throws {
        let root = ViewNode.selectedContentBoundary(role: .viewThatFits, child: ViewNode())
        let runtime = RetainedViewRuntime(root: root)
        defer { retireBoundaryRuntime(runtime) }
        runtime.setRootSize(IntSize(width: 120, height: 40))
        var calls = 0
        let button = makeBoundaryButton(runtime: runtime, label: "Save") { calls += 1 }
        root.setChildren([button])
        _ = runtime.renderFrame()
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: runtime))
        XCTAssertTrue(projection.sourceNode === button)
        XCTAssertEqual(projection.flattened().count, 1)
        XCTAssertTrue(root.children.first === button)
        XCTAssertTrue(button.parent === root)
        XCTAssertEqual(button.resolvedFrame, Rect(x: 0, y: 0, width: 120, height: 40))
        XCTAssertEqual(button.frame, .zero, "Root canvas assignment must not rewrite authored child geometry")
        XCTAssertNil(root.onActivate)
        XCTAssertFalse(root.isFocusable)

        let snapshots = source.uiaElementSnapshots()
        XCTAssertEqual(snapshots.count, 1)
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.id, UIAProviderBridge.rootElementID)
        XCTAssertNil(snapshot.parentID)
        XCTAssertEqual(snapshot.name, "Save")
        XCTAssertEqual(snapshot.controlType, Int32(SWU_UIA_CONTROL_TYPE_BUTTON))
        XCTAssertEqual(snapshot.bounds, Rect(x: 0, y: 0, width: 120, height: 40))
        XCTAssertTrue(snapshot.isKeyboardFocusable)
        XCTAssertTrue(snapshot.hasDefaultAction)

        runtime.pointerDown(at: Point(x: 5, y: 5))
        runtime.pointerUp(at: Point(x: 5, y: 5))
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(runtime.focusedNode === button)
        runtime.requestFocus(nil)
        XCTAssertTrue(source.uiaSetFocusResult(elementID: UIAProviderBridge.rootElementID))
        XCTAssertTrue(runtime.focusedNode === button)
        XCTAssertEqual(source.projectedElementID(forNodeOrAncestor: button), UIAProviderBridge.rootElementID)
        XCTAssertTrue(try XCTUnwrap(source.uiaElementSnapshots().first).hasKeyboardFocus)
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: UIAProviderBridge.rootElementID))
        XCTAssertEqual(calls, 2)

        runtime.setRootSize(IntSize(width: 160, height: 60))
        _ = runtime.renderFrame()
        XCTAssertEqual(root.frame.size, Size(width: 160, height: 60))
        XCTAssertEqual(button.frame, .zero)
        XCTAssertEqual(button.resolvedFrame, Rect(x: 0, y: 0, width: 160, height: 60))
        XCTAssertEqual(try XCTUnwrap(source.uiaElementSnapshots().first).bounds, button.resolvedFrame)
        runtime.pointerDown(at: Point(x: 150, y: 50))
        runtime.pointerUp(at: Point(x: 150, y: 50))
        XCTAssertEqual(calls, 3)
    }

    func testRootUIAFocusDoesNotRetargetAfterItsSelectedPathChanges() async throws {
        let root = ViewNode.selectedContentBoundary(role: .viewThatFits, child: ViewNode())
        let runtime = RetainedViewRuntime(root: root)
        defer { retireBoundaryRuntime(runtime) }
        runtime.setRootSize(IntSize(width: 120, height: 40))
        var oldCalls = 0
        var replacementCalls = 0
        var oldEntries = 0
        var replacementEntries = 0
        let old = makeBoundaryButton(runtime: runtime, label: "Old") { oldCalls += 1 }
        let replacement = makeBoundaryButton(runtime: runtime, label: "Replacement") { replacementCalls += 1 }
        root.setChildren([old])
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        _ = source.uiaElementSnapshots()
        old.onFocusEnter = {
            oldEntries += 1
            root.setChildren([replacement])
        }
        replacement.onFocusEnter = { replacementEntries += 1 }

        XCTAssertFalse(source.uiaSetFocusResult(elementID: UIAProviderBridge.rootElementID))
        XCTAssertEqual(oldEntries, 1)
        XCTAssertEqual(replacementEntries, 0, "One request must not acquire the replacement's target")
        XCTAssertTrue(root.children.first === replacement)
        XCTAssertTrue(replacement.parent === root)
        XCTAssertNil(old.parent)
        XCTAssertFalse(runtime.focusedNode === old)
        XCTAssertNil(source.projectedElementID(forNodeOrAncestor: old))
        let snapshot = try XCTUnwrap(source.uiaElementSnapshots().first)
        XCTAssertEqual(snapshot.id, UIAProviderBridge.rootElementID)
        XCTAssertEqual(snapshot.name, "Replacement")
        XCTAssertTrue(source.uiaSetFocusResult(elementID: UIAProviderBridge.rootElementID))
        XCTAssertEqual(replacementEntries, 1)
        XCTAssertTrue(runtime.focusedNode === replacement)
        XCTAssertEqual(source.projectedElementID(forNodeOrAncestor: replacement), UIAProviderBridge.rootElementID)
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: UIAProviderBridge.rootElementID))
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(replacementCalls, 1)
    }
}

@MainActor
private func wrapBoundary(_ selected: ViewNode, depth: Int) -> ViewNode {
    var physical = selected
    for _ in 0..<depth {
        physical = ViewNode.selectedContentBoundary(role: .viewThatFits, child: physical)
    }
    return physical
}

@MainActor
private func assertZeroOriginBoundaryPath(
    _ physical: ViewNode, endingAt selected: ViewNode,
    file: StaticString = #filePath, line: UInt = #line
) {
    var node = physical
    var remaining = 3
    while node !== selected, remaining > 0 {
        guard case .viewThatFits? = node.selectedContentRole else {
            return XCTFail("An ordinary node cannot be unwrapped", file: file, line: line)
        }
        XCTAssertEqual(node.resolvedFrame.origin, .zero, file: file, line: line)
        XCTAssertEqual(node.children.count, 1, file: file, line: line)
        guard let child = node.children.first else { return }
        XCTAssertTrue(child.parent === node, file: file, line: line)
        node = child
        remaining -= 1
    }
    XCTAssertTrue(node === selected, file: file, line: line)
}

@MainActor
private func makeBoundaryRuntime(operand: ViewNode, size: IntSize) -> RetainedViewRuntime {
    let runtime = RetainedViewRuntime(root: ViewNode(children: [operand]))
    runtime.setRootSize(size)
    return runtime
}

@MainActor
private func retireBoundaryRuntime(_ runtime: RetainedViewRuntime) {
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    runtime.root.removeAllChildren()
}

private func boundaryFills(_ frame: RenderFrame) -> [FillRectCommand] {
    frame.commands.compactMap { command in
        guard case .fillRect(let fill) = command else { return nil }
        return fill
    }
}

@MainActor
private func makeBoundaryButton(
    runtime: RetainedViewRuntime, label: String, action: @escaping () -> Void
) -> ViewNode {
    let button = Controls.button(
        runtime: runtime, frame: .zero, cornerRadius: 0,
        palette: SurfacePalette(idle: .gray, focused: .blue, pressed: .black), action: action)
    button.accessibilityLabel = label
    button.accessibilityTraits = .isButton
    return button
}
