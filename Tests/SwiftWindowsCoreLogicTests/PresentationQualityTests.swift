import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

@MainActor
private func makePresentationContext(
    size: Size = Size(width: 800, height: 600),
    onInvalidate: @escaping () -> Void = {}
) -> ViewBuildContext {
    ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: onInvalidate)
}

@MainActor
private func makePresentationRuntime(size: Size = Size(width: 800, height: 600)) -> RetainedViewRuntime {
    let runtime = RetainedViewRuntime(root: ViewNode())
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    return runtime
}

@MainActor
private func makeMenuNode<V: View>(
    _ view: V,
    runtime: RetainedViewRuntime,
    context: ViewBuildContext
) -> ViewNode {
    view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func presentationAllTexts(in node: ViewNode) -> [String] {
    var texts: [String] = []
    if let text = node.text {
        texts.append(text)
    }
    for child in node.children {
        texts.append(contentsOf: presentationAllTexts(in: child))
    }
    return texts
}

@MainActor
private func presentationFocusableNodes(in node: ViewNode) -> [ViewNode] {
    var nodes: [ViewNode] = node.isFocusable ? [node] : []
    for child in node.children {
        nodes.append(contentsOf: presentationFocusableNodes(in: child))
    }
    return nodes
}

private func presentationSceneQuadColors(in scene: GPUIScene) -> [Color] {
    scene.layers.flatMap { layer in
        layer.quads.map { quad in
            Color(red: quad.startR, green: quad.startG, blue: quad.startB, alpha: quad.startA)
        }
    }
}

private let presentationCanvasSize = Size(width: 800, height: 600)

final class PresentationQualityTests: XCTestCase {

    // MARK: - Placement

    func testOpenMenuPanelAnchorsBelowButtonWhenSpaceAllows() async {
        await MainActor.run {
            let runtime = makePresentationRuntime(size: presentationCanvasSize)
            let context = makePresentationContext(size: presentationCanvasSize)
            let menu = Menu("ACTIONS") {
                Button("EXPORT") {}
            }

            let collapsedNode = makeMenuNode(menu, runtime: runtime, context: context)
            collapsedNode.children[0].onActivate?()

            let node = makeMenuNode(menu, runtime: runtime, context: context)
            node.frame = Rect(x: 40, y: 40, width: 160, height: 200)
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            XCTAssertEqual(node.children.count, 2)
            let overlayContainer = node.children[1]
            XCTAssertEqual(overlayContainer.children.count, 2)
            let panel = overlayContainer.children[1]

            let buttonHeight = node.children[0].frame.height
            XCTAssertEqual(panel.frame.origin.x, 0, accuracy: 0.001)
            // The menu root's bounds resolve to the button's intrinsic size
            // (root preferredSize), so the +4 gap clamps and the panel anchors
            // at the button's bottom edge.
            XCTAssertEqual(panel.frame.origin.y, buttonHeight, accuracy: 0.001)

            // No clamping needed: the panel stays at its natural anchor.
            let panelBottom = node.frame.origin.y + panel.frame.origin.y + panel.frame.height
            XCTAssertLessThanOrEqual(panelBottom, presentationCanvasSize.height + 0.001)
        }
    }

    func testOpenMenuPanelIsClampedToCanvasBounds() async {
        await MainActor.run {
            let runtime = makePresentationRuntime(size: presentationCanvasSize)
            let context = makePresentationContext(size: presentationCanvasSize)
            let menu = Menu("ACTIONS") {
                Button("EXPORT") {}
                Button("ARCHIVE") {}
            }

            let collapsedNode = makeMenuNode(menu, runtime: runtime, context: context)
            collapsedNode.children[0].onActivate?()

            // Place the menu at the bottom-right corner so the natural
            // below-button placement would paint off-canvas on both axes.
            let node = makeMenuNode(menu, runtime: runtime, context: context)
            node.frame = Rect(x: 790, y: 580, width: 120, height: 40)
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            let panel = node.children[1].children[1]
            let panelOrigin = Point(
                x: node.frame.origin.x + panel.frame.origin.x,
                y: node.frame.origin.y + panel.frame.origin.y
            )

            XCTAssertGreaterThanOrEqual(panelOrigin.x, -0.001)
            XCTAssertGreaterThanOrEqual(panelOrigin.y, -0.001)
            XCTAssertEqual(panelOrigin.x + panel.frame.width, presentationCanvasSize.width, accuracy: 0.001)
            XCTAssertEqual(panelOrigin.y + panel.frame.height, presentationCanvasSize.height, accuracy: 0.001)
        }
    }

    // MARK: - Dismissal

    func testOutsidePointerDownDismissesOpenMenu() async {
        await MainActor.run {
            var didInvalidate = false
            let runtime = makePresentationRuntime(size: presentationCanvasSize)
            let context = makePresentationContext(size: presentationCanvasSize) {
                didInvalidate = true
            }
            let menu = Menu("ACTIONS") {
                Button("EXPORT") {}
            }

            let collapsedNode = makeMenuNode(menu, runtime: runtime, context: context)
            collapsedNode.children[0].onActivate?()
            XCTAssertTrue(didInvalidate)
            didInvalidate = false

            let node = makeMenuNode(menu, runtime: runtime, context: context)
            node.frame = Rect(x: 40, y: 40, width: 160, height: 200)
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            let overlayContainer = node.children[1]
            let scrim = overlayContainer.children[0]
            let panel = overlayContainer.children[1]

            // The scrim covers the whole canvas from the menu's position.
            XCTAssertEqual(scrim.frame, Rect(x: -40, y: -40, width: 800, height: 600))
            // The panel swallows padding clicks so they do not dismiss.
            XCTAssertTrue(panel.isHitTestVisible)

            // Pointer-down on the panel itself must not dismiss.
            let panelCenter = Point(
                x: node.frame.origin.x + panel.frame.origin.x + panel.frame.width / 2,
                y: node.frame.origin.y + panel.frame.origin.y + 2
            )
            runtime.pointerDown(at: panelCenter)
            XCTAssertFalse(didInvalidate)

            // Pointer-down anywhere outside the overlay dismisses the menu.
            runtime.pointerDown(at: Point(x: 400, y: 300))
            XCTAssertTrue(didInvalidate)

            node.removeFromParent()
            let dismissedNode = makeMenuNode(menu, runtime: runtime, context: context)
            XCTAssertEqual(dismissedNode.children.count, 1)
            XCTAssertFalse(presentationAllTexts(in: dismissedNode).contains("EXPORT"))
        }
    }

    func testEscapeDismissesOpenMenuAndRestoresFocusToMenuButton() async {
        await MainActor.run {
            var didInvalidate = false
            let runtime = makePresentationRuntime(size: presentationCanvasSize)
            let context = makePresentationContext(size: presentationCanvasSize) {
                didInvalidate = true
            }
            let menu = Menu("ACTIONS") {
                Button("EXPORT") {}
            }

            let collapsedNode = makeMenuNode(menu, runtime: runtime, context: context)
            collapsedNode.frame = Rect(x: 40, y: 40, width: 160, height: 40)
            runtime.root.addChild(collapsedNode)
            _ = runtime.renderFrame()

            let collapsedButton = collapsedNode.children[0]
            runtime.requestFocus(collapsedButton)
            XCTAssertTrue(collapsedButton.isFocused)

            collapsedButton.onActivate?()
            XCTAssertTrue(didInvalidate)
            didInvalidate = false

            collapsedNode.removeFromParent()
            let openNode = makeMenuNode(menu, runtime: runtime, context: context)
            openNode.frame = Rect(x: 40, y: 40, width: 160, height: 40)
            runtime.root.addChild(openNode)
            _ = runtime.renderFrame()

            let openButton = openNode.children[0]
            runtime.requestFocus(openButton)

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
            XCTAssertTrue(didInvalidate)

            openNode.removeFromParent()
            let restoredNode = makeMenuNode(menu, runtime: runtime, context: context)
            XCTAssertEqual(restoredNode.children.count, 1)
            XCTAssertTrue(
                restoredNode.children[0].isFocused,
                "Dismissing the menu should restore focus to its source button"
            )
        }
    }

    func testEscapeFromFocusedMenuItemDismissesMenu() async {
        await MainActor.run {
            var didInvalidate = false
            let runtime = makePresentationRuntime(size: presentationCanvasSize)
            let context = makePresentationContext(size: presentationCanvasSize) {
                didInvalidate = true
            }
            let menu = Menu("ACTIONS") {
                Button("EXPORT") {}
                Button("ARCHIVE") {}
            }

            let collapsedNode = makeMenuNode(menu, runtime: runtime, context: context)
            collapsedNode.children[0].onActivate?()
            didInvalidate = false

            let openNode = makeMenuNode(menu, runtime: runtime, context: context)
            openNode.frame = Rect(x: 40, y: 40, width: 160, height: 40)
            runtime.root.addChild(openNode)
            _ = runtime.renderFrame()

            let exportItem = presentationFocusableNodes(in: openNode.children[1]).first {
                presentationAllTexts(in: $0).contains("EXPORT")
            }
            guard let exportItem else {
                return XCTFail("Expected a focusable EXPORT menu item")
            }
            runtime.requestFocus(exportItem)

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
            XCTAssertTrue(didInvalidate)

            openNode.removeFromParent()
            let dismissedNode = makeMenuNode(menu, runtime: runtime, context: context)
            XCTAssertEqual(dismissedNode.children.count, 1)
            XCTAssertFalse(presentationAllTexts(in: dismissedNode).contains("EXPORT"))
        }
    }

    // MARK: - Layering and shadow chrome

    func testOpenMenuOverlayPaintsInDeferredPhaseAboveBaseContent() async {
        await MainActor.run {
            let runtime = makePresentationRuntime(size: presentationCanvasSize)
            let context = makePresentationContext(size: presentationCanvasSize)
            let menu = Menu("ACTIONS") {
                Button("EXPORT") {}
            }

            let collapsedNode = makeMenuNode(menu, runtime: runtime, context: context)
            collapsedNode.children[0].onActivate?()

            let openNode = makeMenuNode(menu, runtime: runtime, context: context)
            openNode.frame = Rect(x: 40, y: 40, width: 160, height: 40)

            // A sibling painted after the menu in base order would cover the
            // menu panel unless the overlay paints in the deferred phase.
            let lateSibling = ViewNode(
                frame: Rect(x: 0, y: 0, width: 800, height: 600),
                backgroundColor: .white
            )
            runtime.root.addChild(openNode)
            runtime.root.addChild(lateSibling)

            let overlayContainer = openNode.children[1]
            XCTAssertTrue(
                overlayContainer.paintsInDeferredPhase,
                "Open menu overlay must paint in the deferred phase"
            )

            let scene = runtime.renderScene()
            let colors = presentationSceneQuadColors(in: scene)
            let panelColor = Color(red: 0.108, green: 0.108, blue: 0.108, alpha: 0.96)

            func firstIndex(matching target: Color) -> Int? {
                colors.firstIndex { color in
                    abs(color.red - target.red) < 0.01
                        && abs(color.green - target.green) < 0.01
                        && abs(color.blue - target.blue) < 0.01
                        && abs(color.alpha - target.alpha) < 0.01
                }
            }

            guard let panelIndex = firstIndex(matching: panelColor) else {
                return XCTFail("Expected the menu panel background quad in the scene")
            }
            guard let siblingIndex = firstIndex(matching: .white) else {
                return XCTFail("Expected the late sibling quad in the scene")
            }
            XCTAssertGreaterThan(
                panelIndex,
                siblingIndex,
                "Deferred menu overlay must paint after base content"
            )
        }
    }

    func testOpenMenuPanelKeepsSoftShadowChrome() async {
        await MainActor.run {
            let runtime = makePresentationRuntime(size: presentationCanvasSize)
            let context = makePresentationContext(size: presentationCanvasSize)
            let menu = Menu("ACTIONS") {
                Button("EXPORT") {}
            }

            let collapsedNode = makeMenuNode(menu, runtime: runtime, context: context)
            collapsedNode.children[0].onActivate?()

            let openNode = makeMenuNode(menu, runtime: runtime, context: context)
            let panel = openNode.children[1].children[1]

            XCTAssertGreaterThan(panel.shadowColor.alpha, 0)
            XCTAssertGreaterThan(panel.shadowSpread, 0)
            XCTAssertEqual(panel.shadowOffset, Point(x: 0, y: 10))
            XCTAssertEqual(panel.cornerRadius, 10)
        }
    }
}
