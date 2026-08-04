import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

@MainActor
private func makeOverlayContext(
    size: Size = Size(width: 800, height: 600),
    onInvalidate: @escaping () -> Void = {}
) -> ViewBuildContext {
    ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: onInvalidate)
}

@MainActor
private func makeOverlayRuntime(size: Size = Size(width: 800, height: 600)) -> RetainedViewRuntime {
    let runtime = RetainedViewRuntime(root: ViewNode())
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    return runtime
}

@MainActor
private func makeOverlayNode<V: View>(
    _ view: V,
    runtime: RetainedViewRuntime,
    context: ViewBuildContext
) -> ViewNode {
    view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func overlayAllTexts(in node: ViewNode) -> [String] {
    var texts: [String] = []
    if let text = node.text {
        texts.append(text)
    }
    for child in node.children {
        texts.append(contentsOf: overlayAllTexts(in: child))
    }
    return texts
}

@MainActor
private func overlayFocusableNode(containing text: String, in node: ViewNode) -> ViewNode? {
    if node.isFocusable, overlayAllTexts(in: node).contains(text) {
        return node
    }
    for child in node.children {
        if let match = overlayFocusableNode(containing: text, in: child) {
            return match
        }
    }
    return nil
}

@MainActor
private func overlayFirstFocusableNode(in node: ViewNode) -> ViewNode? {
    if node.isFocusable {
        return node
    }
    for child in node.children {
        if let match = overlayFirstFocusableNode(in: child) {
            return match
        }
    }
    return nil
}

private func overlaySceneQuadColors(in scene: GPUIScene) -> [Color] {
    scene.layers.flatMap { layer in
        layer.quads.map { quad in
            Color(red: quad.startR, green: quad.startG, blue: quad.startB, alpha: quad.startA)
        }
    }
}

private let overlayCanvasSize = Size(width: 800, height: 600)
private let overlayCanvasFrame = Rect(x: 0, y: 0, width: 800, height: 600)

final class PresentationOverlayTests: XCTestCase {

    // MARK: - Deferred-phase layering

    func testSheetOverlayPaintsInDeferredPhaseAboveBaseContent() async {
        await MainActor.run {
            let runtime = makeOverlayRuntime(size: overlayCanvasSize)
            let context = makeOverlayContext(size: overlayCanvasSize)
            var presented = true
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            let view = Text("BASE").sheet(isPresented: binding) {
                Text("SHEET CONTENT")
            }

            let node = makeOverlayNode(view, runtime: runtime, context: context)
            node.frame = overlayCanvasFrame

            // A sibling painted after the sheet in base order would cover the
            // sheet unless the overlay paints in the deferred phase.
            let lateSibling = ViewNode(
                frame: overlayCanvasFrame,
                backgroundColor: .white
            )
            runtime.root.addChild(node)
            runtime.root.addChild(lateSibling)

            XCTAssertEqual(node.children.count, 2)
            let overlayContainer = node.children[1]
            XCTAssertEqual(overlayContainer.nodeTag, "sheet-overlay")
            XCTAssertTrue(
                overlayContainer.paintsInDeferredPhase,
                "Presented sheet overlay must paint in the deferred phase"
            )

            let scene = runtime.renderScene()
            let colors = overlaySceneQuadColors(in: scene)
            // Neutral, not navy: the sheet surface follows the desaturated
            // chrome ramp.
            let sheetColor = Color(red: 0.146, green: 0.146, blue: 0.146, alpha: 0.98)

            func firstIndex(matching target: Color) -> Int? {
                colors.firstIndex { color in
                    abs(color.red - target.red) < 0.01
                        && abs(color.green - target.green) < 0.01
                        && abs(color.blue - target.blue) < 0.01
                        && abs(color.alpha - target.alpha) < 0.01
                }
            }

            guard let sheetIndex = firstIndex(matching: sheetColor) else {
                return XCTFail("Expected the sheet background quad in the scene")
            }
            guard let siblingIndex = firstIndex(matching: .white) else {
                return XCTFail("Expected the late sibling quad in the scene")
            }
            XCTAssertGreaterThan(
                sheetIndex,
                siblingIndex,
                "Deferred sheet overlay must paint after base content"
            )
        }
    }

    func testFullScreenCoverPaintsInDeferredPhaseAndSwallowsClicks() async {
        await MainActor.run {
            let runtime = makeOverlayRuntime(size: overlayCanvasSize)
            let context = makeOverlayContext(size: overlayCanvasSize)
            var presented = true
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            let view = Text("BASE").fullScreenCover(isPresented: binding) {
                Text("COVER CONTENT")
            }

            let node = makeOverlayNode(view, runtime: runtime, context: context)
            node.frame = overlayCanvasFrame
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            XCTAssertEqual(node.children.count, 2)
            let overlayContainer = node.children[1]
            XCTAssertEqual(overlayContainer.nodeTag, "full-screen-cover-overlay")
            XCTAssertTrue(overlayContainer.paintsInDeferredPhase)
            XCTAssertEqual(overlayContainer.frame, overlayCanvasFrame)

            let cover = overlayContainer.children[0]
            XCTAssertTrue(
                cover.isHitTestVisible,
                "Modal cover must swallow clicks instead of falling through to base content"
            )
            XCTAssertEqual(cover.frame, overlayCanvasFrame)
        }
    }

    // MARK: - Sheet dismissal

    func testSheetScrimCoversCanvasAndOutsideActivationDismisses() async {
        await MainActor.run {
            var didInvalidate = false
            let runtime = makeOverlayRuntime(size: overlayCanvasSize)
            let context = makeOverlayContext(size: overlayCanvasSize) {
                didInvalidate = true
            }
            var presented = true
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            let view = Text("BASE").sheet(isPresented: binding) {
                Text("SHEET CONTENT")
            }

            let node = makeOverlayNode(view, runtime: runtime, context: context)
            node.frame = overlayCanvasFrame
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            let overlayContainer = node.children[1]
            let scrim = overlayContainer.children[0]
            let sheet = overlayContainer.children[1]

            XCTAssertEqual(scrim.nodeTag, "sheet-scrim-dismiss-enabled")
            XCTAssertEqual(scrim.frame, overlayCanvasFrame)
            XCTAssertTrue(
                sheet.isHitTestVisible,
                "Sheet panel must swallow padding clicks so they do not dismiss"
            )

            scrim.onActivate?()
            XCTAssertFalse(presented)
            XCTAssertTrue(didInvalidate)
        }
    }

    func testEscapeDismissesSheetFromFocusedSheetContent() async {
        await MainActor.run {
            let runtime = makeOverlayRuntime(size: overlayCanvasSize)
            let context = makeOverlayContext(size: overlayCanvasSize)
            var presented = true
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            let view = Text("BASE").sheet(isPresented: binding) {
                Button("CLOSE") {}
            }

            let node = makeOverlayNode(view, runtime: runtime, context: context)
            node.frame = overlayCanvasFrame
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            guard let closeButton = overlayFocusableNode(containing: "CLOSE", in: node) else {
                return XCTFail("Expected a focusable CLOSE button in the sheet")
            }
            runtime.requestFocus(closeButton)
            XCTAssertTrue(closeButton.isFocused)

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
            XCTAssertFalse(presented, "Escape must dismiss the presented sheet")
        }
    }

    // MARK: - Focus restoration

    func testSheetDismissalRestoresFocusToPreviouslyFocusedControl() async {
        await MainActor.run {
            let runtime = makeOverlayRuntime(size: overlayCanvasSize)
            let context = makeOverlayContext(size: overlayCanvasSize)
            var presented = false
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            var name = "ADA"
            let nameBinding = Binding<String>(get: { name }, set: { name = $0 })
            let view = VStack {
                TextField("NAME", text: nameBinding)
            }
            .sheet(isPresented: binding) {
                Button("CLOSE") {}
            }

            let collapsedNode = makeOverlayNode(view, runtime: runtime, context: context)
            collapsedNode.frame = overlayCanvasFrame
            runtime.root.addChild(collapsedNode)
            _ = runtime.renderFrame()

            guard let textField = overlayFirstFocusableNode(in: collapsedNode) else {
                return XCTFail("Expected a focusable text field in the base content")
            }
            runtime.requestFocus(textField)
            XCTAssertTrue(textField.isFocused)

            // Present while the text field is still attached and focused so the
            // presentation captures it as the focus-restoration target.
            presented = true
            let presentedNode = makeOverlayNode(view, runtime: runtime, context: context)
            presentedNode.frame = overlayCanvasFrame
            runtime.root.addChild(presentedNode)
            _ = runtime.renderFrame()

            // Move focus into the sheet, then dismiss: focus must return to
            // the text field that was focused at presentation time.
            guard let closeButton = overlayFocusableNode(containing: "CLOSE", in: presentedNode) else {
                return XCTFail("Expected a focusable CLOSE button in the sheet")
            }
            runtime.requestFocus(closeButton)
            XCTAssertFalse(textField.isFocused)

            let scrim = presentedNode.children[1].children[0]
            scrim.onActivate?()
            XCTAssertFalse(presented)
            XCTAssertTrue(
                runtime.focusedNode === textField,
                "Dismissing the sheet should restore focus to the control focused at presentation time"
            )
            XCTAssertTrue(textField.isFocused)
            XCTAssertFalse(closeButton.isFocused)

            collapsedNode.removeFromParent()
            presentedNode.removeFromParent()
        }
    }

    func testSheetDismissalFallsBackToFirstBaseControlWhenNothingWasFocused() async {
        await MainActor.run {
            let runtime = makeOverlayRuntime(size: overlayCanvasSize)
            let context = makeOverlayContext(size: overlayCanvasSize)
            var presented = true
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            let view = VStack {
                Button("OPEN") {}
            }
            .sheet(isPresented: binding) {
                Button("CLOSE") {}
            }

            let node = makeOverlayNode(view, runtime: runtime, context: context)
            node.frame = overlayCanvasFrame
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            // Focus lands inside the sheet while nothing was focused in the
            // base content at presentation time.
            guard let closeButton = overlayFocusableNode(containing: "CLOSE", in: node) else {
                return XCTFail("Expected a focusable CLOSE button in the sheet")
            }
            runtime.requestFocus(closeButton)

            guard let openButton = overlayFocusableNode(containing: "OPEN", in: node.children[0]) else {
                return XCTFail("Expected a focusable OPEN button in the base content")
            }

            let scrim = node.children[1].children[0]
            scrim.onActivate?()
            XCTAssertFalse(presented)
            XCTAssertTrue(
                runtime.focusedNode === openButton,
                "With nothing focused at presentation time, focus should fall back to the base content's source control"
            )
        }
    }

    // MARK: - Popover

    func testPopoverIsClampedToCanvasAndDismissesOnOutsidePointerDown() async {
        await MainActor.run {
            let runtime = makeOverlayRuntime(size: overlayCanvasSize)
            let context = makeOverlayContext(size: overlayCanvasSize)
            var presented = true
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            let view = Text("BASE").popover(
                isPresented: binding,
                attachmentAnchor: .rect(UnitPoint(x: 1, y: 1)),
                arrowEdge: .top
            ) {
                Text("POPOVER CONTENT")
            }

            let node = makeOverlayNode(view, runtime: runtime, context: context)
            node.frame = overlayCanvasFrame
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            XCTAssertEqual(node.children.count, 2)
            let overlayContainer = node.children[1]
            XCTAssertEqual(overlayContainer.nodeTag, "popover-overlay")
            XCTAssertTrue(overlayContainer.paintsInDeferredPhase)

            let scrim = overlayContainer.children[0]
            let popover = overlayContainer.children[1]
            XCTAssertEqual(scrim.nodeTag, "popover-dismiss-scrim")
            XCTAssertEqual(scrim.frame, overlayCanvasFrame)
            XCTAssertTrue(popover.isHitTestVisible)

            // The bottom-right attachment must clamp the popover on-canvas.
            XCTAssertGreaterThanOrEqual(popover.frame.origin.x, -0.001)
            XCTAssertGreaterThanOrEqual(popover.frame.origin.y, -0.001)
            XCTAssertLessThanOrEqual(popover.frame.maxX, overlayCanvasSize.width + 0.001)
            XCTAssertLessThanOrEqual(popover.frame.maxY, overlayCanvasSize.height + 0.001)

            // Pointer-down on the popover's padding must not dismiss.
            runtime.pointerDown(
                at: Point(
                    x: popover.frame.origin.x + popover.frame.width / 2,
                    y: popover.frame.origin.y + 2
                )
            )
            XCTAssertTrue(presented)

            // Pointer-down anywhere outside the popover dismisses it.
            runtime.pointerDown(at: Point(x: 5, y: 5))
            XCTAssertFalse(presented)
        }
    }

    // MARK: - Alert

    func testAlertScrimBlocksWithoutDismissingAndEscapeDismisses() async {
        await MainActor.run {
            var didInvalidate = false
            let runtime = makeOverlayRuntime(size: overlayCanvasSize)
            let context = makeOverlayContext(size: overlayCanvasSize) {
                didInvalidate = true
            }
            var presented = true
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            let view = Text("BASE").alert("DELETE", isPresented: binding) {
                Button("OK") {}
            }

            let node = makeOverlayNode(view, runtime: runtime, context: context)
            node.frame = overlayCanvasFrame
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            XCTAssertEqual(node.children.count, 2)
            let overlayContainer = node.children[1]
            XCTAssertEqual(overlayContainer.nodeTag, "alert-overlay")
            XCTAssertTrue(overlayContainer.paintsInDeferredPhase)

            let scrim = overlayContainer.children[0]
            let alert = overlayContainer.children[1]
            XCTAssertEqual(scrim.nodeTag, "alert-scrim")
            XCTAssertEqual(scrim.frame, overlayCanvasFrame)
            XCTAssertTrue(scrim.isHitTestVisible, "Alert scrim must block background interaction")
            XCTAssertTrue(alert.isHitTestVisible)

            // Outside clicks are swallowed by the modal scrim but do not
            // dismiss, matching SwiftUI alert behavior.
            runtime.pointerDown(at: Point(x: 20, y: 20))
            XCTAssertTrue(presented)
            XCTAssertFalse(didInvalidate)

            guard let okButton = overlayFocusableNode(containing: "OK", in: node) else {
                return XCTFail("Expected a focusable OK button in the alert")
            }
            runtime.requestFocus(okButton)
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
            XCTAssertFalse(presented, "Escape must dismiss the presented alert")
            XCTAssertTrue(didInvalidate)
        }
    }

    // MARK: - Confirmation dialog

    func testConfirmationDialogDismissesOnOutsidePointerDownOnly() async {
        await MainActor.run {
            let runtime = makeOverlayRuntime(size: overlayCanvasSize)
            let context = makeOverlayContext(size: overlayCanvasSize)
            var presented = true
            let binding = Binding<Bool>(get: { presented }, set: { presented = $0 })
            let view = Text("BASE")
                .frame(width: overlayCanvasSize.width, height: overlayCanvasSize.height)
                .confirmationDialog("PICK", isPresented: binding) {
                    Button("FIRST") {}
                }

            let node = makeOverlayNode(view, runtime: runtime, context: context)
            node.frame = overlayCanvasFrame
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            XCTAssertEqual(node.children.count, 2)
            let overlayContainer = node.children[1]
            XCTAssertEqual(overlayContainer.nodeTag, "confirmation-dialog-overlay")
            XCTAssertTrue(overlayContainer.paintsInDeferredPhase)

            let scrim = overlayContainer.children[0]
            let dialog = overlayContainer.children[1]
            XCTAssertEqual(scrim.nodeTag, "confirmation-dialog-scrim")
            XCTAssertEqual(scrim.frame, overlayCanvasFrame)
            XCTAssertTrue(dialog.isHitTestVisible)

            // Pointer-down on the dialog's own padding must not dismiss.
            runtime.pointerDown(
                at: Point(
                    x: dialog.frame.origin.x + dialog.frame.width / 2,
                    y: dialog.frame.origin.y + 2
                )
            )
            XCTAssertTrue(presented)

            // Pointer-down anywhere outside the dialog dismisses it.
            runtime.pointerDown(at: Point(x: 20, y: 20))
            XCTAssertFalse(presented)
        }
    }

    // MARK: - Context menu

    func testContextMenuOverlayClampsDismissesOutsideAndOnEscape() async {
        await MainActor.run {
            var didInvalidate = false
            let runtime = makeOverlayRuntime(size: overlayCanvasSize)
            let context = makeOverlayContext(size: overlayCanvasSize) {
                didInvalidate = true
            }
            let view = Text("ROW")
                .frame(width: overlayCanvasSize.width, height: overlayCanvasSize.height)
                .contextMenu {
                    Button("COPY") {}
                }

            let collapsedNode = makeOverlayNode(view, runtime: runtime, context: context)
            collapsedNode.frame = overlayCanvasFrame
            runtime.root.addChild(collapsedNode)
            _ = runtime.renderFrame()

            // Invoke the context menu near the bottom-right corner.
            collapsedNode.onContextMenu?(Point(x: 700, y: 500))
            XCTAssertTrue(didInvalidate)
            didInvalidate = false

            collapsedNode.removeFromParent()
            let node = makeOverlayNode(view, runtime: runtime, context: context)
            node.frame = overlayCanvasFrame
            runtime.root.addChild(node)
            _ = runtime.renderFrame()

            XCTAssertEqual(node.children.count, 2)
            let overlayContainer = node.children[1]
            XCTAssertEqual(overlayContainer.nodeTag, "context-menu-overlay")
            XCTAssertTrue(overlayContainer.paintsInDeferredPhase)

            let scrim = overlayContainer.children[0]
            let panel = overlayContainer.children[1]
            XCTAssertEqual(scrim.nodeTag, "context-menu-dismiss-scrim")
            XCTAssertEqual(scrim.frame, overlayCanvasFrame)
            XCTAssertTrue(panel.isHitTestVisible)

            // The panel must clamp on-canvas from the corner anchor.
            XCTAssertGreaterThanOrEqual(panel.frame.origin.x, -0.001)
            XCTAssertGreaterThanOrEqual(panel.frame.origin.y, -0.001)
            XCTAssertLessThanOrEqual(panel.frame.maxX, overlayCanvasSize.width + 0.001)
            XCTAssertLessThanOrEqual(panel.frame.maxY, overlayCanvasSize.height + 0.001)

            // Pointer-down outside the panel dismisses the menu.
            runtime.pointerDown(at: Point(x: 20, y: 20))
            XCTAssertTrue(didInvalidate)

            node.removeFromParent()
            let dismissedNode = makeOverlayNode(view, runtime: runtime, context: context)
            XCTAssertFalse(overlayAllTexts(in: dismissedNode).contains("COPY"))

            // Re-invoke and dismiss via Escape from a focused menu item.
            didInvalidate = false
            dismissedNode.frame = overlayCanvasFrame
            runtime.root.addChild(dismissedNode)
            _ = runtime.renderFrame()
            dismissedNode.onContextMenu?(Point(x: 100, y: 100))
            dismissedNode.removeFromParent()

            let reopenedNode = makeOverlayNode(view, runtime: runtime, context: context)
            reopenedNode.frame = overlayCanvasFrame
            runtime.root.addChild(reopenedNode)
            _ = runtime.renderFrame()

            guard let copyItem = overlayFocusableNode(containing: "COPY", in: reopenedNode) else {
                return XCTFail("Expected a focusable COPY menu item")
            }
            runtime.requestFocus(copyItem)
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))
            XCTAssertTrue(didInvalidate, "Escape must dismiss the open context menu")

            reopenedNode.removeFromParent()
            let escapedNode = makeOverlayNode(view, runtime: runtime, context: context)
            XCTAssertFalse(overlayAllTexts(in: escapedNode).contains("COPY"))
            escapedNode.removeFromParent()
            dismissedNode.removeFromParent()
        }
    }
}
