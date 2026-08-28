import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
private final class RevealClampController: RetainedTextInputController {
    func attach(to node: ViewNode) {}
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func detach(from node: ViewNode) {}
}

@MainActor
private final class RevealClampClock {
    var now = 0.0
}

@MainActor
private final class RevealClampFixture {
    let runtime: RetainedViewRuntime
    let editor: ViewNode
    let viewport: ViewNode
    let content: ViewNode
    let outer: ViewNode
    let outerTarget: ViewNode
    let controller: RevealClampController
    let clock = RevealClampClock()
    let usesScene: Bool

    init(usesScene: Bool) {
        self.usesScene = usesScene
        content = ViewNode(frame: Rect(x: 0, y: 0, width: 180, height: 400))
        viewport = ViewNode(
            frame: Rect(x: 10, y: 10, width: 180, height: 80),
            clipsToBounds: true, scrollAxis: .vertical, children: [content])
        editor = ViewNode(frame: Rect(x: 20, y: 20, width: 200, height: 100), children: [viewport])
        editor.isFocusable = true
        editor.accessibilityTraits.insert(.isTextInput)
        controller = RevealClampController()
        editor.textInputController = controller
        outerTarget = ViewNode(frame: Rect(x: 0, y: 500, width: 20, height: 16))
        outer = ViewNode(
            frame: Rect(x: 0, y: 0, width: 240, height: 140),
            clipsToBounds: true, scrollAxis: .vertical, children: [editor, outerTarget])
        runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300), children: [outer]))
        let clock = self.clock
        runtime.clock = { clock.now }
        runtime.requestFocus(editor)
        render()
    }

    func render() {
        if usesScene {
            _ = runtime.renderScene()
        } else {
            _ = runtime.renderFrame()
        }
    }

    func reveal(y: Double, height: Double = 16) -> Bool {
        runtime.revealTextInputRect(
            Rect(x: 12, y: y, width: 0, height: height),
            in: viewport, ownedBy: editor, controller: controller)
    }
}

@MainActor
final class TextEditorRevealClampTests: XCTestCase {
    func testContentShrinkNormalizesVisibleCaretOffsetWithoutInterruptingTheOuterTween() async {
        for usesScene in [false, true] {
            for caretHeight in [16.0, 120.0] {
                let fixture = RevealClampFixture(usesScene: usesScene)
                fixture.viewport.scrollOffset = 200
                fixture.render()
                XCTAssertEqual(fixture.viewport.resolvedScrollOffset, 200)

                fixture.content.frame.size.height = 40
                fixture.render()
                XCTAssertEqual(fixture.content.resolvedFrame.size.height, 40)
                XCTAssertEqual(fixture.viewport.resolvedContentSize.height, 80)
                XCTAssertEqual(fixture.viewport.resolvedScrollOffset, 0)
                XCTAssertEqual(
                    fixture.viewport.scrollOffset, 200,
                    "The fixture must retain the obsolete logical request")
                XCTAssertTrue(
                    fixture.runtime.scrollToDescendant(
                        fixture.outerTarget, anchorY: 0, transaction: Transaction(animation: .linear(duration: 1))))
                let outerOffset = fixture.outer.scrollOffset
                let outerDelta = fixture.outer.scrollPresentedDelta
                XCTAssertNotEqual(outerDelta, 0)

                for _ in 0..<2 {
                    XCTAssertTrue(fixture.reveal(y: 0, height: caretHeight))
                    XCTAssertEqual(fixture.viewport.scrollOffset, 0)
                    XCTAssertEqual(fixture.viewport.scrollPresentedDelta, 0)
                    XCTAssertEqual(fixture.outer.scrollOffset, outerOffset)
                    XCTAssertEqual(fixture.outer.scrollPresentedDelta, outerDelta)
                    XCTAssertTrue(fixture.runtime.focusedNode === fixture.editor)
                    XCTAssertTrue(fixture.editor.textInputController === fixture.controller)
                }

                fixture.content.frame.size.height = 400
                fixture.render()
                XCTAssertEqual(fixture.viewport.scrollOffset, 0)
                XCTAssertEqual(fixture.viewport.resolvedScrollOffset, 0, "Later growth must not revive the old offset")
                fixture.clock.now = 0.25
                _ = fixture.runtime.tickAnimations(at: fixture.clock.now)
                XCTAssertGreaterThan(fixture.outer.scrollPresentedDelta, outerDelta)
                XCTAssertEqual(fixture.viewport.scrollOffset, 0)
            }
        }
    }

    func testVisibleCaretNormalizesBothLogicalBoundsOnBothRenderPaths() async {
        for usesScene in [false, true] {
            for (requested, caretY, expected) in [(1_000.0, 330.0, 320.0), (-50.0, 12.0, 0.0)] {
                let fixture = RevealClampFixture(usesScene: usesScene)
                fixture.viewport.scrollOffset = requested
                fixture.render()
                XCTAssertEqual(fixture.viewport.scrollOffset, requested)
                XCTAssertEqual(fixture.viewport.resolvedScrollOffset, expected)

                XCTAssertTrue(fixture.reveal(y: caretY))

                XCTAssertEqual(fixture.viewport.scrollOffset, expected)
                XCTAssertEqual(fixture.outer.scrollOffset, 0)
                XCTAssertTrue(fixture.runtime.focusedNode === fixture.editor)
                XCTAssertTrue(fixture.editor.textInputController === fixture.controller)
                fixture.render()
                XCTAssertEqual(fixture.viewport.resolvedScrollOffset, expected)
                XCTAssertTrue(fixture.reveal(y: caretY))
                XCTAssertEqual(fixture.viewport.scrollOffset, expected)
            }
        }
    }

    func testKeyboardTweenWithAnOutOfRangeTargetNormalizesAtTheVisibleCaret() async {
        for usesScene in [false, true] {
            let content = ViewNode(frame: Rect(x: 0, y: 0, width: 180, height: 400))
            let viewport = ViewNode(
                frame: Rect(x: 10, y: 10, width: 180, height: 80),
                clipsToBounds: true, scrollAxis: .vertical, children: [content])
            let editor = ViewNode(frame: Rect(x: 20, y: 20, width: 200, height: 100), children: [viewport])
            editor.isFocusable = true
            editor.accessibilityTraits.insert(.isTextInput)
            editor.interceptsVerticalArrowKeys = true
            let controller = RevealClampController()
            editor.textInputController = controller
            // No outer scroll container: focus stays on the editor while
            // PageDown routes through the hovered content to its viewport.
            let runtime = RetainedViewRuntime(
                root: ViewNode(frame: Rect(x: 0, y: 0, width: 240, height: 140), children: [editor]))
            let clock = RevealClampClock()
            runtime.clock = { clock.now }
            let render: @MainActor () -> Void = {
                if usesScene {
                    _ = runtime.renderScene()
                } else {
                    _ = runtime.renderFrame()
                }
            }
            runtime.requestFocus(editor)
            viewport.scrollOffset = 200
            render()
            XCTAssertEqual(viewport.resolvedFrame.size.height, 80)
            XCTAssertEqual(viewport.resolvedContentSize.height, 400)
            XCTAssertEqual(viewport.resolvedScrollOffset, 200)
            let hoverPoint = Point(x: 40, y: 40)
            XCTAssertTrue(runtime.focusedNode === editor)
            runtime.pointerMoved(to: hoverPoint)
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.pageDown.rawValue))
            render()
            XCTAssertEqual(viewport.scrollOffset, 268)
            XCTAssertEqual(viewport.scrollPresentedDelta, -68)
            XCTAssertEqual(viewport.resolvedScrollOffset, 200)

            // An in-range target keeps its keyboard tween when the caret
            // is visible. Only the subsequent shrink requires normalization.
            XCTAssertTrue(
                runtime.revealTextInputRect(
                    Rect(x: 12, y: 212, width: 0, height: 16),
                    in: viewport, ownedBy: editor, controller: controller))
            XCTAssertEqual(viewport.scrollOffset, 268)
            XCTAssertEqual(viewport.scrollPresentedDelta, -68)

            content.frame.size.height = 320
            render()
            XCTAssertEqual(viewport.resolvedContentSize.height, 320)
            XCTAssertEqual(viewport.scrollOffset, 268)
            XCTAssertEqual(viewport.scrollPresentedDelta, -68)
            XCTAssertEqual(viewport.resolvedScrollOffset, 172, "The clamped target is 240 with a -68 keyboard delta")
            let caret = Rect(x: 12, y: 180, width: 0, height: 16)
            XCTAssertGreaterThanOrEqual(caret.minY, viewport.resolvedScrollOffset)
            XCTAssertLessThanOrEqual(caret.maxY, viewport.resolvedScrollOffset + viewport.resolvedFrame.size.height)

            for _ in 0..<2 {
                XCTAssertTrue(runtime.revealTextInputRect(caret, in: viewport, ownedBy: editor, controller: controller))
                XCTAssertEqual(viewport.scrollOffset, 172)
                XCTAssertEqual(viewport.scrollPresentedDelta, 0)
                render()
                XCTAssertEqual(viewport.resolvedScrollOffset, 172)
                XCTAssertGreaterThanOrEqual(caret.minY, viewport.resolvedScrollOffset)
                XCTAssertLessThanOrEqual(caret.maxY, viewport.resolvedScrollOffset + viewport.resolvedFrame.size.height)
            }

            content.frame.size.height = 400
            render()
            XCTAssertEqual(viewport.resolvedContentSize.height, 400)
            XCTAssertEqual(viewport.scrollOffset, 172)
            XCTAssertEqual(viewport.scrollPresentedDelta, 0)
            XCTAssertEqual(viewport.resolvedScrollOffset, 172)
            XCTAssertGreaterThanOrEqual(caret.minY, viewport.resolvedScrollOffset)
            XCTAssertLessThanOrEqual(caret.maxY, viewport.resolvedScrollOffset + viewport.resolvedFrame.size.height)
            clock.now = 0.055
            _ = runtime.tickAnimations(at: clock.now)
            render()
            XCTAssertEqual(viewport.scrollOffset, 172)
            XCTAssertEqual(
                viewport.scrollPresentedDelta, 0, "The cancelled keyboard tween must not resume after growth")
            XCTAssertEqual(viewport.resolvedScrollOffset, 172)
            XCTAssertGreaterThanOrEqual(caret.minY, viewport.resolvedScrollOffset)
            XCTAssertLessThanOrEqual(caret.maxY, viewport.resolvedScrollOffset + viewport.resolvedFrame.size.height)
            XCTAssertTrue(runtime.focusedNode === editor)
            XCTAssertTrue(editor.textInputController === controller)
        }
    }
}
