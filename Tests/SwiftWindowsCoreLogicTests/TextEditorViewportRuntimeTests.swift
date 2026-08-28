import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
private final class ViewportFixtureController: RetainedTextInputController {
    weak var node: ViewNode?

    func attach(to node: ViewNode) { self.node = node }

    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        self.node = node
    }

    func detach(from node: ViewNode) {
        if self.node === node { self.node = nil }
    }
}

@MainActor
private final class ViewportRuntimeClock {
    var now = 0.0
}

/// Exercises the retained viewport contract without text shaping, an HWND,
/// native input, or the facade's controller and document ownership machinery.
@MainActor
final class TextEditorViewportRuntimeTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let runtime: RetainedViewRuntime
        let editor: ViewNode
        let viewport: ViewNode
        let content: ViewNode
        let contentTarget: ViewNode
        let outer: ViewNode
        let outerTarget: ViewNode
        let unrelated: ViewNode
        let controller: ViewportFixtureController
        let clock: ViewportRuntimeClock

        func reveal(_ rect: Rect) -> Bool {
            runtime.revealTextInputRect(rect, in: viewport, ownedBy: editor, controller: controller)
        }

        func scheduleReveal(_ rect: Rect, key: String = "caret", completion: @escaping @MainActor (Bool) -> Void) {
            runtime.scheduleAfterLayout(key: key) {
                [weak runtime, weak viewport, weak editor, weak controller] in
                guard let runtime, let viewport, let editor, let controller else { return }
                completion(
                    runtime.revealTextInputRect(rect, in: viewport, ownedBy: editor, controller: controller))
            }
        }
    }

    private func fixture(render: Bool = true) -> Fixture {
        let contentTarget = ViewNode(frame: Rect(x: 0, y: 300, width: 10, height: 16))
        let content = ViewNode(
            frame: Rect(x: 0, y: 0, width: 188, height: 400), children: [contentTarget])
        let viewport = ViewNode(
            frame: Rect(x: 6, y: 8, width: 188, height: 84),
            clipsToBounds: true,
            scrollAxis: .vertical,
            children: [content])
        let editor = ViewNode(preferredSize: Size(width: 200, height: 100), children: [viewport])
        editor.isFocusable = true
        editor.accessibilityTraits.insert(.isTextInput)
        editor.interceptsVerticalArrowKeys = true
        let controller = ViewportFixtureController()
        editor.textInputController = controller

        let outerTarget = ViewNode(frame: Rect(x: 0, y: 300, width: 10, height: 16))
        let tail = ViewNode(preferredSize: Size(width: 200, height: 500), children: [outerTarget])
        let outer = ViewNode(
            frame: Rect(x: 10, y: 20, width: 220, height: 120),
            clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, padding: .zero, alignment: .leading)),
            scrollAxis: .vertical,
            children: [editor, tail])
        let unrelated = ViewNode(frame: Rect(x: 300, y: 20, width: 40, height: 40))
        let runtime = RetainedViewRuntime(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 500, height: 400), children: [outer, unrelated]))
        let clock = ViewportRuntimeClock()
        runtime.clock = { clock.now }
        runtime.requestFocus(editor)
        if render { _ = runtime.renderScene() }
        return Fixture(
            runtime: runtime, editor: editor, viewport: viewport, content: content,
            contentTarget: contentTarget, outer: outer, outerTarget: outerTarget, unrelated: unrelated,
            controller: controller, clock: clock)
    }

    private func caret(y: Double, height: Double = 16) -> Rect {
        Rect(x: 12, y: y, width: 0, height: height)
    }

    func testZeroWidthCaretUsesMinimalVerticalMovementAndContentClamping() async {
        let current = fixture()
        current.outer.scrollOffset = 20
        XCTAssertTrue(current.reveal(caret(y: 12)))
        XCTAssertEqual(current.viewport.scrollOffset, 0)

        XCTAssertTrue(current.reveal(caret(y: 140)))
        XCTAssertEqual(current.viewport.scrollOffset, 72)
        XCTAssertTrue(current.reveal(caret(y: 90)))
        XCTAssertEqual(current.viewport.scrollOffset, 72, "A visible caret does not move the viewport")
        XCTAssertTrue(current.reveal(caret(y: 20)))
        XCTAssertEqual(current.viewport.scrollOffset, 20)
        XCTAssertTrue(current.reveal(caret(y: 900)))
        XCTAssertEqual(current.viewport.scrollOffset, 316)
        XCTAssertTrue(current.reveal(caret(y: -40)))
        XCTAssertEqual(current.viewport.scrollOffset, 0)
        XCTAssertEqual(current.outer.scrollOffset, 20)
    }

    func testProgrammaticRevealStillWorksWhenViewportScrollInputIsDisabled() async {
        let current = fixture()
        current.viewport.isScrollInputEnabled = false

        XCTAssertTrue(current.reveal(caret(y: 140)))
        XCTAssertEqual(current.viewport.scrollOffset, 72)
        XCTAssertFalse(current.viewport.isScrollInputEnabled)
        XCTAssertEqual(current.outer.scrollOffset, 0)
    }

    func testCaretTallerThanViewportHasAnIdempotentMinimalReveal() async {
        let current = fixture()
        current.viewport.frame.size.height = 10
        _ = current.runtime.renderScene()

        for _ in 0..<3 {
            XCTAssertTrue(current.reveal(caret(y: 0, height: 20)))
            XCTAssertEqual(current.viewport.scrollOffset, 0)
        }
        for _ in 0..<3 {
            XCTAssertTrue(current.reveal(caret(y: 140, height: 20)))
            XCTAssertEqual(current.viewport.scrollOffset, 150)
        }
        XCTAssertTrue(current.reveal(caret(y: 100, height: 20)))
        XCTAssertEqual(current.viewport.scrollOffset, 100)
    }

    func testAlreadyVisibleCaretLeavesOwnedScrollTweenRunning() async {
        let current = fixture()
        XCTAssertTrue(
            current.runtime.scrollToDescendant(
                current.contentTarget, anchorY: 0, transaction: Transaction(animation: .linear(duration: 1))))
        let targetOffset = current.viewport.scrollOffset
        let presentedDelta = current.viewport.scrollPresentedDelta
        XCTAssertNotEqual(presentedDelta, 0)

        XCTAssertTrue(current.reveal(caret(y: 12)))
        XCTAssertEqual(current.viewport.scrollOffset, targetOffset)
        XCTAssertEqual(current.viewport.scrollPresentedDelta, presentedDelta)
        current.clock.now = 0.25
        _ = current.runtime.tickAnimations(at: current.clock.now)
        XCTAssertGreaterThan(current.viewport.scrollPresentedDelta, presentedDelta)
    }

    func testNeededRevealCancelsOnlyOwnedMotionAndKeepsAncestorTween() async {
        let current = fixture()
        XCTAssertTrue(
            current.runtime.scrollToDescendant(
                current.contentTarget, anchorY: 0, transaction: Transaction(animation: .linear(duration: 1))))
        XCTAssertTrue(
            current.runtime.scrollToDescendant(
                current.outerTarget, anchorY: 0, transaction: Transaction(animation: .linear(duration: 1))))
        let outerOffset = current.outer.scrollOffset
        let outerDelta = current.outer.scrollPresentedDelta
        XCTAssertNotEqual(current.viewport.scrollPresentedDelta, 0)
        XCTAssertNotEqual(outerDelta, 0)

        XCTAssertTrue(current.reveal(caret(y: 140)))
        XCTAssertEqual(current.viewport.scrollOffset, 72)
        XCTAssertEqual(current.viewport.scrollPresentedDelta, 0)
        XCTAssertEqual(current.outer.scrollOffset, outerOffset)
        XCTAssertEqual(current.outer.scrollPresentedDelta, outerDelta)
        current.clock.now = 0.25
        _ = current.runtime.tickAnimations(at: current.clock.now)
        XCTAssertEqual(current.viewport.scrollOffset, 72)
        XCTAssertEqual(current.viewport.scrollPresentedDelta, 0)
        XCTAssertGreaterThan(current.outer.scrollPresentedDelta, outerDelta)
    }

    func testRevealRejectsBeforeFirstLayoutAndDuringLayout() async {
        let current = fixture(render: false)
        XCTAssertFalse(current.reveal(caret(y: 140)))
        var attempts = 0
        current.viewport.onLayout = {
            [
                weak runtime = current.runtime, weak viewport = current.viewport,
                weak editor = current.editor, weak controller = current.controller
            ] _ in
            guard let runtime, let viewport, let editor, let controller else { return }
            attempts += 1
            XCTAssertTrue(runtime.isLayoutInProgress)
            XCTAssertFalse(
                runtime.revealTextInputRect(
                    Rect(x: 0, y: 140, width: 0, height: 16),
                    in: viewport, ownedBy: editor, controller: controller))
        }

        _ = current.runtime.renderScene()
        XCTAssertGreaterThan(attempts, 0)
        XCTAssertEqual(current.viewport.scrollOffset, 0)
    }

    func testPendingViewportResizeWaitsForCompleteLayout() async {
        let current = fixture()
        current.viewport.frame.size.height = 100
        XCTAssertTrue(current.runtime.hasPendingLayout)
        XCTAssertFalse(current.reveal(caret(y: 140)))
        XCTAssertEqual(current.viewport.scrollOffset, 0)
        var results: [Bool] = []
        current.scheduleReveal(caret(y: 140)) { results.append($0) }

        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [true])
        XCTAssertEqual(current.viewport.scrollOffset, 56)
        XCTAssertEqual(current.viewport.resolvedScrollOffset, 56)
    }

    func testQueuedRevealSettlesImmediateGeometryQueryBeforeAnyPaint() async throws {
        let current = fixture(render: false)
        var results: [Bool] = []
        current.scheduleReveal(caret(y: 140)) { results.append($0) }

        let contentFrame = try XCTUnwrap(current.runtime.resolvedLayoutFrame(of: current.content))
        XCTAssertEqual(results, [true])
        XCTAssertEqual(current.viewport.scrollOffset, 72)
        XCTAssertEqual(current.viewport.resolvedScrollOffset, 72)
        XCTAssertEqual(contentFrame.origin, Point(x: 16, y: -44))
        XCTAssertEqual(current.outer.scrollOffset, 0)
    }

    func testQueuedRevealWorksOnBothSceneAndFramePathsWithoutRepeating() async {
        for scene in [true, false] {
            let current = fixture(render: false)
            var results: [Bool] = []
            current.scheduleReveal(caret(y: 140)) { results.append($0) }
            if scene {
                _ = current.runtime.renderScene()
                _ = current.runtime.renderScene()
            } else {
                _ = current.runtime.renderFrame()
                _ = current.runtime.renderFrame()
            }
            XCTAssertEqual(results, [true])
            XCTAssertEqual(current.viewport.resolvedScrollOffset, 72)
        }
    }

    func testEarlierAfterLayoutViewportMutationDefersTheStaleRequest() async {
        let current = fixture()
        var results: [Bool] = []
        current.runtime.scheduleAfterLayout(key: "resize") { [weak viewport = current.viewport] in
            viewport?.frame.size.height = 100
        }
        current.scheduleReveal(caret(y: 140)) { results.append($0) }

        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [false])
        XCTAssertEqual(current.viewport.scrollOffset, 0)
        XCTAssertEqual(current.viewport.resolvedFrame.height, 100)

        current.scheduleReveal(caret(y: 140)) { results.append($0) }
        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [false, true])
        XCTAssertEqual(current.viewport.scrollOffset, 56)
    }

    func testEarlierAfterLayoutContentMutationDefersTheStaleRequest() async {
        let current = fixture()
        var results: [Bool] = []
        current.runtime.scheduleAfterLayout(key: "replace-content") { [weak content = current.content] in
            content?.frame.size.height = 600
        }
        current.scheduleReveal(caret(y: 140)) { results.append($0) }

        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [false])
        XCTAssertEqual(current.viewport.scrollOffset, 0)

        current.scheduleReveal(caret(y: 500)) { results.append($0) }
        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [false, true])
        XCTAssertEqual(current.viewport.scrollOffset, 432)
    }

    func testEarlierAfterLayoutAncestorMutationDefersTheStaleRequest() async {
        let current = fixture()
        var results: [Bool] = []
        current.runtime.scheduleAfterLayout(key: "resize-outer") { [weak outer = current.outer] in
            outer?.frame.size.width = 210
        }
        current.scheduleReveal(caret(y: 140)) { results.append($0) }

        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [false])
        XCTAssertEqual(current.viewport.scrollOffset, 0)
    }

    func testEarlierAfterLayoutDisplayScaleChangeDefersTheStaleTextLayout() async {
        let current = fixture()
        var results: [Bool] = []
        current.runtime.scheduleAfterLayout(key: "change-scale") { [weak runtime = current.runtime] in
            runtime?.displayScale = 1.5
        }
        current.scheduleReveal(caret(y: 140)) { results.append($0) }

        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [false])
        XCTAssertEqual(current.viewport.scrollOffset, 0)
        current.scheduleReveal(caret(y: 140)) { results.append($0) }
        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [false, true])
        XCTAssertEqual(current.viewport.scrollOffset, 72)
    }

    func testUnrelatedGeometryAndPaintChangesDoNotBlockDrainedReveal() async {
        let current = fixture()
        var results: [Bool] = []
        current.runtime.scheduleAfterLayout(key: "unrelated") {
            [weak unrelated = current.unrelated, weak editor = current.editor] in
            unrelated?.frame.size.height = 50
            editor?.opacity = 0.8
        }
        current.scheduleReveal(caret(y: 140)) { results.append($0) }

        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [true])
        XCTAssertEqual(current.viewport.scrollOffset, 72)
    }

    func testEarlierSiblingGrowthDefersUntilTheEditorsNewViewportIsPlaced() async {
        let current = fixture()
        let preceding = ViewNode(preferredSize: Size(width: 200, height: 20))
        current.editor.removeFromParent()
        current.outer.removeAllChildren()
        current.outer.scrollAxis = nil
        current.outer.addChild(preceding)
        current.outer.addChild(current.editor)
        current.editor.layoutMode = .stack(.vertical(spacing: 0, padding: .zero, alignment: .stretch))
        current.editor.forwardsStackMainAxisProposal = true
        current.viewport.frame = .zero
        current.viewport.layoutFillAxes = .both
        current.runtime.requestFocus(current.editor)
        _ = current.runtime.renderScene()
        let previousHeight = current.viewport.resolvedFrame.height
        XCTAssertEqual(previousHeight, 100)

        var results: [Bool] = []
        current.runtime.scheduleAfterLayout(key: "grow-sibling") { [weak preceding] in
            preceding?.preferredSize = Size(width: 200, height: 100)
        }
        current.scheduleReveal(caret(y: 140)) { results.append($0) }
        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [false])
        XCTAssertEqual(current.viewport.scrollOffset, 0)
        XCTAssertLessThan(current.viewport.resolvedFrame.height, previousHeight)

        current.scheduleReveal(caret(y: 140)) { results.append($0) }
        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [false, true])
        XCTAssertEqual(current.viewport.scrollOffset, 156 - current.viewport.resolvedFrame.height)
    }

    func testRevealRejectsInvalidAndNonfiniteRectangles() async {
        let current = fixture()
        let invalid = [
            Rect(x: .nan, y: 140, width: 0, height: 16),
            Rect(x: 0, y: .infinity, width: 0, height: 16),
            Rect(x: 0, y: 140, width: -.infinity, height: 16),
            Rect(x: 0, y: 140, width: -1, height: 16),
            Rect(x: 0, y: 140, width: 0, height: .nan),
            Rect(x: 0, y: 140, width: 0, height: 0),
            Rect(x: 0, y: 140, width: 0, height: -1),
            Rect(x: 0, y: .greatestFiniteMagnitude, width: 0, height: .greatestFiniteMagnitude),
        ]
        for rect in invalid { XCTAssertFalse(current.reveal(rect)) }
        XCTAssertEqual(current.viewport.scrollOffset, 0)
        XCTAssertEqual(current.outer.scrollOffset, 0)
    }

    func testRevealRejectsAnEmptyOrNonfiniteResolvedViewport() async {
        for size in [Size(width: 188, height: 0), Size(width: 0, height: 84), Size(width: 188, height: .nan)] {
            let current = fixture()
            current.viewport.resolvedFrame.size = size
            XCTAssertFalse(current.reveal(caret(y: 140)))
            XCTAssertEqual(current.viewport.scrollOffset, 0)
        }
    }

    func testRevealRejectsDetachedEditorAndViewport() async {
        for detachEditor in [true, false] {
            let current = fixture()
            if detachEditor {
                current.editor.removeFromParent()
            } else {
                current.viewport.removeFromParent()
            }
            _ = current.runtime.renderScene()
            XCTAssertFalse(current.runtime.hasPendingLayout)
            XCTAssertFalse(current.reveal(caret(y: 140)))
            XCTAssertEqual(current.viewport.scrollOffset, 0)
            XCTAssertEqual(current.outer.scrollOffset, 0)
        }
    }

    func testRevealRejectsReplacedControllerButAllowsTheCurrentController() async {
        let current = fixture()
        let replacement = ViewportFixtureController()
        current.editor.textInputController = replacement
        _ = current.runtime.renderScene()

        XCTAssertFalse(current.reveal(caret(y: 140)))
        XCTAssertEqual(current.viewport.scrollOffset, 0)
        XCTAssertTrue(
            current.runtime.revealTextInputRect(
                caret(y: 140), in: current.viewport, ownedBy: current.editor, controller: replacement))
        XCTAssertEqual(current.viewport.scrollOffset, 72)
        XCTAssertTrue(replacement.node === current.editor)
    }

    func testRevealRejectsForeignRuntimeAndUnrelatedViewport() async {
        let current = fixture()
        let foreign = fixture()
        XCTAssertFalse(
            foreign.runtime.revealTextInputRect(
                caret(y: 140), in: current.viewport, ownedBy: current.editor, controller: current.controller))
        XCTAssertFalse(
            current.runtime.revealTextInputRect(
                caret(y: 140), in: current.outer, ownedBy: current.editor, controller: current.controller))
        XCTAssertEqual(current.viewport.scrollOffset, 0)
        XCTAssertEqual(current.outer.scrollOffset, 0)
        XCTAssertEqual(foreign.viewport.scrollOffset, 0)
    }

    func testRevealRejectsAnIndirectViewportInsteadOfFindingAnAncestor() async {
        let current = fixture()
        current.viewport.removeFromParent()
        let wrapper = ViewNode(preferredSize: Size(width: 200, height: 100), children: [current.viewport])
        current.editor.addChild(wrapper)
        _ = current.runtime.renderScene()

        XCTAssertFalse(current.reveal(caret(y: 140)))
        XCTAssertEqual(current.viewport.scrollOffset, 0)
        XCTAssertEqual(current.outer.scrollOffset, 0)
    }

    func testRevealRejectsHiddenUnfocusedDeferredAndUnclippedOwners() async {
        let mutations: [(Fixture) -> Void] = [
            { $0.editor.isHidden = true },
            { $0.viewport.isHidden = true },
            { $0.outer.isHidden = true },
            { $0.runtime.requestFocus(nil) },
            { $0.viewport.isLayoutDeferredByVirtualization = true },
            { $0.outer.isLayoutDeferredByVirtualization = true },
            { $0.viewport.clipsToBounds = false },
            { $0.viewport.scrollAxis = .horizontal },
        ]
        for mutate in mutations {
            let current = fixture()
            mutate(current)
            _ = current.runtime.renderScene()
            XCTAssertFalse(current.runtime.hasPendingLayout)
            XCTAssertFalse(current.reveal(caret(y: 140)))
            XCTAssertEqual(current.viewport.scrollOffset, 0)
        }
    }

    func testEarlierAfterLayoutControllerReplacementCannotUseTheCapturedOwner() async {
        let current = fixture()
        let replacement = ViewportFixtureController()
        var results: [Bool] = []
        current.runtime.scheduleAfterLayout(key: "replace-controller") { [weak editor = current.editor] in
            editor?.textInputController = replacement
        }
        current.scheduleReveal(caret(y: 140)) { results.append($0) }

        _ = current.runtime.renderScene()
        XCTAssertEqual(results, [false])
        XCTAssertEqual(current.viewport.scrollOffset, 0)
        XCTAssertTrue(current.editor.textInputController === replacement)
    }

    func testTextEditorNavigationKeysAndSelectionModifiersPrecedeOuterScrolling() async {
        let keys: [KeyboardKey] = [.upArrow, .downArrow, .home, .end]
        let modifiers: [KeyboardModifiers] = [[], [.shift], [.control], [.control, .shift]]
        for key in keys {
            for modifier in modifiers {
                let current = fixture()
                current.outer.scrollOffset = 50
                var received: [KeyboardEvent] = []
                current.editor.onKeyDown = { received.append($0) }

                current.runtime.keyDown(KeyboardEvent(keyCode: key.rawValue, modifiers: modifier))
                XCTAssertEqual(received.count, 1)
                XCTAssertEqual(received.first?.key, key)
                XCTAssertEqual(received.first?.modifiers, modifier)
                XCTAssertEqual(current.outer.scrollOffset, 50)
                XCTAssertEqual(current.viewport.scrollOffset, 0)
            }
        }
    }

    func testEditorNavigationDoesNotCancelAnOuterProgrammaticTween() async {
        let current = fixture()
        XCTAssertTrue(
            current.runtime.scrollToDescendant(
                current.outerTarget, anchorY: 0, transaction: Transaction(animation: .linear(duration: 1))))
        let offset = current.outer.scrollOffset
        let delta = current.outer.scrollPresentedDelta
        var received = 0
        current.editor.onKeyDown = { _ in received += 1 }

        for key in [KeyboardKey.upArrow, .downArrow, .home, .end] {
            current.runtime.keyDown(KeyboardEvent(keyCode: key.rawValue, modifiers: [.control, .shift]))
        }
        XCTAssertEqual(received, 4)
        XCTAssertEqual(current.outer.scrollOffset, offset)
        XCTAssertEqual(current.outer.scrollPresentedDelta, delta)
        current.clock.now = 0.25
        _ = current.runtime.tickAnimations(at: current.clock.now)
        XCTAssertGreaterThan(current.outer.scrollPresentedDelta, delta)
    }

    func testExplicitApplicationShortcutStillWinsBeforeEditorNavigation() async {
        let current = fixture()
        var shortcuts = 0
        var editorKeys = 0
        current.unrelated.keyboardShortcuts = [
            KeyboardShortcutBinding(keyCode: KeyboardKey.end.rawValue, modifiers: [.control])
        ]
        current.unrelated.onActivate = { shortcuts += 1 }
        current.editor.onKeyDown = { _ in editorKeys += 1 }

        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.end.rawValue, modifiers: [.control]))
        XCTAssertEqual(shortcuts, 1)
        XCTAssertEqual(editorKeys, 0)
        XCTAssertEqual(current.outer.scrollOffset, 0)
        XCTAssertEqual(current.viewport.scrollOffset, 0)
    }

    func testNonTextInputInterceptionKeepsOnlyItsExistingUnmodifiedArrowRule() async {
        let current = fixture()
        current.editor.accessibilityTraits.remove(.isTextInput)
        current.outer.scrollOffset = 50
        var received = 0
        current.editor.onKeyDown = { _ in received += 1 }

        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
        XCTAssertEqual(received, 1)
        XCTAssertEqual(current.outer.scrollOffset, 50)
        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue, modifiers: [.shift]))
        XCTAssertEqual(received, 1)
        XCTAssertEqual(current.outer.scrollOffset, 34)
    }

    func testTextInputWithoutEditorInterceptionAndAltNavigationKeepScrollBehavior() async {
        for editorInterception in [true, false] {
            let current = fixture()
            current.editor.interceptsVerticalArrowKeys = editorInterception
            current.outer.scrollOffset = 50
            var received = 0
            current.editor.onKeyDown = { _ in received += 1 }
            let modifiers: KeyboardModifiers = editorInterception ? [.alt] : []

            current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue, modifiers: modifiers))
            XCTAssertEqual(received, 0)
            XCTAssertEqual(current.outer.scrollOffset, 34)
        }
    }
}
