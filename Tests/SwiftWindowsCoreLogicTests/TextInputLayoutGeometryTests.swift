import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class TextInputLayoutGeometryTests: XCTestCase {
    func testResolvedFrameUsesStackPlacementAndPresentedScrollOffsets() async throws {
        let item = ViewNode(preferredSize: Size(width: 60, height: 20))
        let scroll = Controls.scrollPanel(
            axis: .vertical,
            frame: Rect(x: 12, y: 18, width: 80, height: 40),
            preferredSize: Size(width: 80, height: 40),
            stackLayout: .vertical(spacing: 0, padding: .zero, alignment: .leading),
            children: [
                ViewNode(preferredSize: Size(width: 60, height: 60)),
                item,
                ViewNode(preferredSize: Size(width: 60, height: 80)),
            ]
        )
        let root = ViewNode(frame: Rect(x: 3, y: 5, width: 200, height: 200))
        root.addChild(scroll)
        let runtime = RetainedViewRuntime(root: root)

        XCTAssertEqual(item.frame, .zero)
        XCTAssertEqual(runtime.resolvedLayoutFrame(of: item), Rect(x: 15, y: 83, width: 60, height: 20))
        _ = runtime.renderScene()

        scroll.scrollOffset = 20
        scroll.scrollPresentedDelta = -5
        scroll.scrollOvershoot = 2
        let scrolled = try XCTUnwrap(runtime.resolvedLayoutFrame(of: item))
        XCTAssertEqual(scroll.resolvedScrollOffset, 17)
        XCTAssertEqual(scrolled, Rect(x: 15, y: 66, width: 60, height: 20))
        XCTAssertEqual(item.frame, .zero, "Reading layout must not overwrite authored geometry")
    }

    func testResolvedFrameRejectsHiddenDetachedAndForeignNodes() async {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100))
        let item = ViewNode(frame: Rect(x: 4, y: 6, width: 20, height: 30))
        root.addChild(item)
        let runtime = RetainedViewRuntime(root: root)
        let foreign = RetainedViewRuntime(root: ViewNode())

        XCTAssertEqual(runtime.resolvedLayoutFrame(of: item), Rect(x: 4, y: 6, width: 20, height: 30))
        XCTAssertNil(foreign.resolvedLayoutFrame(of: item))
        root.isHidden = true
        XCTAssertNil(runtime.resolvedLayoutFrame(of: item))
        root.isHidden = false
        item.isHidden = true
        XCTAssertNil(runtime.resolvedLayoutFrame(of: item))
        item.isHidden = false
        item.removeFromParent()
        XCTAssertNil(runtime.resolvedLayoutFrame(of: item))
    }

    func testResolvedFrameDoesNotReenterLayoutOrPostLayoutCallbacks() async {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100))
        let item = ViewNode(frame: Rect(x: 4, y: 6, width: 20, height: 30))
        root.addChild(item)
        let runtime = RetainedViewRuntime(root: root)
        var layoutCallbacks = 0
        var afterLayoutCallbacks = 0
        item.onLayout = { [weak runtime, weak item] _ in
            guard let runtime, let item else { return }
            layoutCallbacks += 1
            let countBeforeQuery = layoutCallbacks
            XCTAssertTrue(runtime.isLayoutInProgress)
            XCTAssertNil(runtime.resolvedLayoutFrame(of: item))
            XCTAssertEqual(layoutCallbacks, countBeforeQuery)
        }
        runtime.scheduleAfterLayout(key: "query-during-query") { [weak runtime, weak item] in
            guard let runtime, let item else { return }
            afterLayoutCallbacks += 1
            let countBeforeQuery = layoutCallbacks
            XCTAssertFalse(runtime.isLayoutInProgress)
            XCTAssertNil(runtime.resolvedLayoutFrame(of: item))
            XCTAssertEqual(layoutCallbacks, countBeforeQuery)
        }

        XCTAssertEqual(runtime.resolvedLayoutFrame(of: item), Rect(x: 4, y: 6, width: 20, height: 30))
        // Draining after-layout actions schedules one bounded settle pass
        // after the initial layout. Neither nested query adds another pass.
        XCTAssertEqual(layoutCallbacks, 2)
        XCTAssertEqual(afterLayoutCallbacks, 1)
    }

    func testResolvedFrameRejectsNodeRemovedByPostLayoutCallback() async {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100))
        let item = ViewNode(frame: Rect(x: 4, y: 6, width: 20, height: 30))
        root.addChild(item)
        let runtime = RetainedViewRuntime(root: root)
        runtime.scheduleAfterLayout(key: "remove-queried-node") { [weak item] in
            item?.removeFromParent()
        }

        XCTAssertNil(runtime.resolvedLayoutFrame(of: item))
        XCTAssertNil(item.parent)
    }

    func testResolvedFrameDoesNotReadUnplacedNodesDuringRenderCallbacks() async {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100))
        let item = ViewNode(frame: Rect(x: 4, y: 6, width: 20, height: 30))
        root.addChild(item)
        let runtime = RetainedViewRuntime(root: root)
        var appearCallbacks = 0
        item.onAppear = { [weak runtime, weak root] in
            guard let runtime, let root else { return }
            appearCallbacks += 1
            let fresh = ViewNode(preferredSize: Size(width: 15, height: 15))
            root.addChild(fresh)
            XCTAssertNil(runtime.resolvedLayoutFrame(of: fresh))
        }

        _ = runtime.renderFrame()

        XCTAssertEqual(appearCallbacks, 1)
        XCTAssertEqual(runtime.resolvedLayoutFrame(of: item), Rect(x: 4, y: 6, width: 20, height: 30))
    }

    func testReconciledEditorAttachesWhenTheRetainedSlotHadNoController() async throws {
        let root = ViewNode(frame: Rect(x: 30, y: 40, width: 320, height: 200))
        let runtime = RetainedViewRuntime(root: root)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 320, height: 200) }, invalidateHandler: {})
        var showsEditor = false
        host.setComponents {
            if showsEditor {
                return [TextEditor(text: .constant("abcdef")).id("editor-slot").makeComponent(context: context)]
            }
            return [VStack { Text("Placeholder") }.id("editor-slot").makeComponent(context: context)]
        }
        _ = runtime.renderScene()
        let slot = try XCTUnwrap(root.children.first)
        XCTAssertNil(slot.textInputController)

        showsEditor = true
        host.reload()
        XCTAssertTrue(root.children.first === slot)
        XCTAssertNotNil(slot.textInputController)
        runtime.requestFocus(slot)
        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.home.rawValue))
        _ = runtime.renderScene()

        let content = try XCTUnwrap(slot.children.first(where: { !$0.isHidden }))
        let placedContent = try XCTUnwrap(runtime.resolvedLayoutFrame(of: content))
        let caret = try XCTUnwrap(runtime.focusedTextInputCaretRect)
        XCTAssertGreaterThan(placedContent.origin.x, root.frame.origin.x)
        XCTAssertEqual(caret.origin, placedContent.origin)
    }

    func testAttachedTextInputCallbacksDoNotRetainTheirRuntime() async throws {
        var runtime: RetainedViewRuntime? = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100)))
        weak var observedRuntime = runtime
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 100) }, invalidateHandler: {})
        let node = TextEditor(text: .constant("abcdef"))
            .makeComponent(context: context).makeNode(runtime: try XCTUnwrap(runtime))
        runtime?.root.addChild(node)
        _ = runtime?.renderScene()

        runtime = nil

        XCTAssertNil(observedRuntime)
        XCTAssertNotNil(node.onDragStart)
        node.onDragStart?(Point(x: 10, y: 10))
        XCTAssertFalse(node.isFocused)
        XCTAssertEqual(node.textInputCaretOffset, 6)
    }
}
