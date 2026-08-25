import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Modal behavior belongs to the retained tree rather than to HWND, UIA, or
/// a particular renderer. The same modal trait therefore governs keyboard
/// traversal, global shortcuts, and the accessibility projection.
@MainActor
final class ModalPresentationIsolationTests: XCTestCase {
    private static let canvasSize = IntSize(width: 640, height: 480)
    private static let canvasFrame = Rect(x: 0, y: 0, width: 640, height: 480)

    private struct Fixture {
        let runtime: RetainedViewRuntime
        let background: ViewNode
        let modal: ViewNode
        let first: ViewNode
        let second: ViewNode
    }

    private func control(_ label: String, y: Double = 0) -> ViewNode {
        ViewNode(
            frame: Rect(x: 20, y: y, width: 180, height: 32),
            isFocusable: true,
            isHitTestVisible: true,
            accessibilityLabel: label,
            accessibilityTraits: [.isButton]
        )
    }

    private func fixture() -> Fixture {
        let background = control("Background", y: 20)
        let root = ViewNode(frame: Self.canvasFrame, children: [background])
        let runtime = RetainedViewRuntime(root: root)
        runtime.setRootSize(Self.canvasSize)
        _ = runtime.renderFrame()
        runtime.requestFocus(background)

        let first = control("First modal action", y: 80)
        let second = control("Second modal action", y: 130)
        let modal = ViewNode(
            frame: Self.canvasFrame,
            accessibilityTraits: [.isModal],
            children: [first, second]
        )
        modal.paintsInDeferredPhase = true
        root.addChild(modal)
        _ = runtime.renderFrame()

        return Fixture(runtime: runtime, background: background, modal: modal, first: first, second: second)
    }

    private func makeRuntime<V: View>(
        _ view: V
    ) -> (runtime: RetainedViewRuntime, node: ViewNode) {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Self.canvasFrame))
        runtime.setRootSize(Self.canvasSize)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 640, height: 480) },
            invalidateHandler: {}
        )
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        node.frame = Self.canvasFrame
        runtime.root.addChild(node)
        _ = runtime.renderFrame()
        return (runtime, node)
    }

    private func firstNode(
        in root: ViewNode,
        matching predicate: (ViewNode) -> Bool
    ) -> ViewNode? {
        var pending = [root]
        while let node = pending.popLast() {
            if predicate(node) { return node }
            pending.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    func testTabMovesBackgroundFocusIntoModalAndCyclesWithoutEscaping() async {
        let current = fixture()
        XCTAssertTrue(current.runtime.focusedNode === current.background)

        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertTrue(current.runtime.focusedNode === current.first)

        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertTrue(current.runtime.focusedNode === current.second)

        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertTrue(current.runtime.focusedNode === current.first)
        XCTAssertFalse(current.background.isFocused)
    }

    func testShiftTabCyclesBackwardInsideModal() async {
        let current = fixture()
        current.runtime.requestFocus(current.first)

        current.runtime.keyDown(
            KeyboardEvent(keyCode: KeyboardKey.tab.rawValue, modifiers: [.shift])
        )
        XCTAssertTrue(current.runtime.focusedNode === current.second)

        current.runtime.keyDown(
            KeyboardEvent(keyCode: KeyboardKey.tab.rawValue, modifiers: [.shift])
        )
        XCTAssertTrue(current.runtime.focusedNode === current.first)
    }

    func testBackgroundShortcutCannotActivateBehindModal() async {
        let current = fixture()
        var backgroundActivations = 0
        var backgroundCompositions = 0
        current.background.keyboardShortcuts = [KeyboardShortcutBinding(keyCode: 0x53, modifiers: [.control])]
        current.background.onActivate = { backgroundActivations += 1 }
        current.background.onIMEComposition = { _ in backgroundCompositions += 1 }
        _ = current.runtime.renderFrame()

        current.runtime.imeComposition(IMECompositionEvent(phase: .committed("hidden")))
        current.runtime.keyDown(KeyboardEvent(keyCode: 0x53, modifiers: [.control]))

        XCTAssertEqual(backgroundActivations, 0)
        XCTAssertEqual(backgroundCompositions, 0)
        XCTAssertTrue(current.runtime.focusedNode === current.first)

        let rows = (0..<20).map { _ in
            ViewNode(preferredSize: Size(width: 180, height: 40), isHitTestVisible: false)
        }
        let backgroundScroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 180, height: 120),
            clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0)),
            scrollAxis: .vertical,
            isHitTestVisible: false,
            children: rows
        )
        let root = ViewNode(frame: Self.canvasFrame, isHitTestVisible: false, children: [backgroundScroll])
        let scrollRuntime = RetainedViewRuntime(root: root)
        _ = scrollRuntime.renderFrame()
        scrollRuntime.pointerMoved(to: Point(x: 50, y: 50))

        let modalButton = control("Modal scroll guard", y: 180)
        let modal = ViewNode(
            frame: Self.canvasFrame,
            accessibilityTraits: [.isModal],
            children: [modalButton]
        )
        modal.paintsInDeferredPhase = true
        root.addChild(modal)
        _ = scrollRuntime.renderFrame()
        scrollRuntime.requestFocus(modalButton)
        scrollRuntime.keyDown(KeyboardEvent(keyCode: KeyboardKey.pageDown.rawValue))

        XCTAssertEqual(backgroundScroll.scrollOffset, 0)
    }

    func testMatchingModalShortcutBeatsTheSameBackgroundShortcut() async {
        let current = fixture()
        var backgroundActivations = 0
        var modalActivations = 0
        let shortcut = KeyboardShortcutBinding(keyCode: 0x53, modifiers: [.control])
        current.background.keyboardShortcuts = [shortcut]
        current.background.onActivate = { backgroundActivations += 1 }
        current.second.keyboardShortcuts = [shortcut]
        current.second.onActivate = { modalActivations += 1 }
        _ = current.runtime.renderFrame()

        current.runtime.keyDown(KeyboardEvent(keyCode: 0x53, modifiers: [.control]))

        XCTAssertEqual(backgroundActivations, 0)
        XCTAssertEqual(modalActivations, 1)
        XCTAssertTrue(current.runtime.focusedNode === current.second)
    }

    func testAttachedBackgroundCannotStealModalFocus() async {
        let current = fixture()
        current.runtime.requestFocus(current.first)

        current.runtime.requestFocus(current.background)

        XCTAssertTrue(current.runtime.focusedNode === current.first)
        XCTAssertFalse(current.background.isFocused)
    }

    func testEnterNeverActivatesStaleBackgroundFocus() async {
        let current = fixture()
        var backgroundActivations = 0
        var modalActivations = 0
        current.background.onActivate = { backgroundActivations += 1 }
        current.first.onActivate = { modalActivations += 1 }

        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

        XCTAssertEqual(backgroundActivations, 0)
        XCTAssertEqual(modalActivations, 1)
        XCTAssertTrue(current.runtime.focusedNode === current.first)
    }

    func testModalWithoutFocusableChildrenClearsBackgroundFocus() async {
        let current = fixture()
        current.first.isFocusable = false
        current.second.isFocusable = false

        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))

        XCTAssertNil(current.runtime.focusedNode)
        XCTAssertFalse(current.background.isFocused)
    }

    func testNestedModalWinsThenOuterScopeResumesAfterRemoval() async {
        let current = fixture()
        current.runtime.requestFocus(current.first)

        let nestedFirst = control("Nested first", y: 180)
        let nestedSecond = control("Nested second", y: 230)
        let nested = ViewNode(
            frame: Self.canvasFrame,
            accessibilityTraits: [.isModal],
            children: [nestedFirst, nestedSecond]
        )
        nested.paintsInDeferredPhase = true
        current.modal.addChild(nested)
        _ = current.runtime.renderFrame()

        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertTrue(current.runtime.focusedNode === nestedFirst)
        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertTrue(current.runtime.focusedNode === nestedSecond)
        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertTrue(current.runtime.focusedNode === nestedFirst)

        nested.removeFromParent()
        _ = current.runtime.renderFrame()
        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertTrue(current.runtime.focusedNode === current.first)

        var outerPresented = true
        var innerPresented = true
        let outerBinding = Binding<Bool>(get: { outerPresented }, set: { outerPresented = $0 })
        let innerBinding = Binding<Bool>(get: { innerPresented }, set: { innerPresented = $0 })
        let nestedPresentations = makeRuntime(
            Button("Outer background") {}
                .sheet(isPresented: outerBinding) {
                    Button("Outer action") {}
                        .alert("Inner alert", isPresented: innerBinding) {
                            Button("Inner action") {}
                        }
                }
        )
        let innerAction = firstNode(in: nestedPresentations.node) {
            $0.accessibilityLabel == "Inner action" && $0.isFocusable
        }
        guard let innerAction else {
            return XCTFail("expected focusable nested alert action")
        }
        nestedPresentations.runtime.requestFocus(innerAction)
        nestedPresentations.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))

        XCTAssertFalse(innerPresented, "Escape dismisses the frontmost alert")
        XCTAssertTrue(outerPresented, "the same Escape never cascades into the containing sheet")
    }

    func testFrontmostSiblingModalOwnsTraversalAndAccessibility() async {
        let current = fixture()
        let frontButton = control("Frontmost action", y: 260)
        let frontModal = ViewNode(
            frame: Self.canvasFrame,
            accessibilityTraits: [.isModal],
            children: [frontButton]
        )
        frontModal.paintsInDeferredPhase = true
        frontModal.zIndex = 10
        current.runtime.root.addChild(frontModal)
        _ = current.runtime.renderFrame()

        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertTrue(current.runtime.focusedNode === frontButton)

        let names = AccessibilityProjection.project(runtime: current.runtime)?.flattened().map(\.name) ?? []
        XCTAssertTrue(names.contains("Frontmost action"))
        XCTAssertFalse(names.contains("First modal action"))
        XCTAssertFalse(names.contains("Background"))

        let earlierDeferredAction = control("Global deferred winner")
        let earlierDeferredModal = ViewNode(
            frame: Self.canvasFrame,
            accessibilityTraits: [.isModal],
            children: [earlierDeferredAction]
        )
        earlierDeferredModal.paintsInDeferredPhase = true
        let earlierBranch = ViewNode(frame: Self.canvasFrame, children: [earlierDeferredModal])
        let laterInlineAction = control("Later inline loser")
        let laterInlineModal = ViewNode(
            frame: Self.canvasFrame,
            accessibilityTraits: [.isModal],
            children: [laterInlineAction]
        )
        let laterBranch = ViewNode(frame: Self.canvasFrame, children: [laterInlineModal])
        let globalRoot = ViewNode(frame: Self.canvasFrame, children: [earlierBranch, laterBranch])
        let globalRuntime = RetainedViewRuntime(root: globalRoot)
        _ = globalRuntime.renderFrame()

        for projection in [
            AccessibilityProjection.project(runtime: globalRuntime),
            AccessibilityProjection.project(root: globalRoot),
        ] {
            let scopedNames = projection?.flattened().map(\.name) ?? []
            XCTAssertTrue(scopedNames.contains("Global deferred winner"))
            XCTAssertFalse(scopedNames.contains("Later inline loser"))
        }
    }

    func testAccessibilityProjectionOmitsBlockedBackground() async {
        let current = fixture()

        let runtimeNames = AccessibilityProjection.project(runtime: current.runtime)?.flattened().map(\.name) ?? []
        let rootNames = AccessibilityProjection.project(root: current.runtime.root)?.flattened().map(\.name) ?? []

        for names in [runtimeNames, rootNames] {
            XCTAssertFalse(names.contains("Background"))
            XCTAssertTrue(names.contains("First modal action"))
            XCTAssertTrue(names.contains("Second modal action"))
        }

        let represented = ViewNode(frame: Rect(x: 0, y: 200, width: 180, height: 32))
        let synthetic = ViewNode(
            frame: Rect(x: 4, y: 4, width: 100, height: 20),
            accessibilityLabel: "Synthetic modal representation"
        )
        represented.accessibilityRepresentationChildren = [synthetic]
        current.modal.addChild(represented)
        current.runtime.root.accessibilityChildBehavior = .combine
        _ = current.runtime.renderFrame()

        let combinedNames = AccessibilityProjection.project(runtime: current.runtime)?.flattened().map(\.name) ?? []
        XCTAssertTrue(combinedNames.contains("Synthetic modal representation"))
        XCTAssertFalse(combinedNames.contains("Background"))
    }

    func testAccessibilityProjectionRetainsRootRelativeModalGeometry() async throws {
        let background = control("Blocked background")
        let action = ViewNode(
            frame: Rect(x: 12, y: 15, width: 90, height: 30),
            isFocusable: true,
            accessibilityLabel: "Offset modal action",
            accessibilityTraits: [.isButton]
        )
        let modal = ViewNode(
            frame: Rect(x: 30, y: 40, width: 240, height: 180),
            accessibilityTraits: [.isModal],
            children: [action]
        )
        let container = ViewNode(frame: Rect(x: 70, y: 80, width: 300, height: 240), children: [modal])
        let root = ViewNode(frame: Self.canvasFrame, children: [background, container])
        let runtime = RetainedViewRuntime(root: root)
        _ = runtime.renderFrame()

        let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: runtime))
        let projectedAction = try XCTUnwrap(projection.flattened().first { $0.name == "Offset modal action" })

        XCTAssertEqual(projectedAction.bounds.origin.x, 112, accuracy: 0.001)
        XCTAssertEqual(projectedAction.bounds.origin.y, 135, accuracy: 0.001)
        XCTAssertFalse(projection.flattened().contains { $0.name == "Blocked background" })
    }

    func testHiddenModalDoesNotSuppressVisibleControls() async {
        let current = fixture()
        current.modal.isHidden = true
        _ = current.runtime.renderFrame()

        let names = AccessibilityProjection.project(runtime: current.runtime)?.flattened().map(\.name) ?? []
        XCTAssertTrue(names.contains("Background"))
        XCTAssertFalse(names.contains("First modal action"))

        current.runtime.requestFocus(current.background)
        XCTAssertTrue(current.runtime.focusedNode === current.background)
    }

    func testNonModalTraversalAndShortcutBehaviorRemainUnchanged() async {
        let current = fixture()
        current.modal.accessibilityTraits.subtract(.isModal)
        var backgroundActivations = 0
        current.background.keyboardShortcuts = [KeyboardShortcutBinding(keyCode: 0x53, modifiers: [.control])]
        current.background.onActivate = { backgroundActivations += 1 }
        _ = current.runtime.renderFrame()

        current.runtime.requestFocus(current.second)
        current.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.tab.rawValue))
        XCTAssertTrue(current.runtime.focusedNode === current.background)

        current.runtime.keyDown(KeyboardEvent(keyCode: 0x53, modifiers: [.control]))
        XCTAssertEqual(backgroundActivations, 1)

        let names = AccessibilityProjection.project(runtime: current.runtime)?.flattened().map(\.name) ?? []
        XCTAssertTrue(names.contains("Background"))
        XCTAssertTrue(names.contains("First modal action"))
    }

    func testSheetFullScreenPopoverAlertAndDialogDeclareModalScopes() async {
        let sheet = makeRuntime(
            Button("Background") {}
                .sheet(isPresented: .constant(true)) { Button("Sheet action") {} }
        )
        let fullScreen = makeRuntime(
            Button("Background") {}
                .fullScreenCover(isPresented: .constant(true)) { Button("Cover action") {} }
        )
        let popover = makeRuntime(
            Button("Background") {}
                .popover(isPresented: .constant(true)) { Button("Popover action") {} }
        )
        let alert = makeRuntime(
            Button("Background") {}
                .alert("Alert", isPresented: .constant(true)) { Button("Alert action") {} }
        )
        let dialog = makeRuntime(
            Button("Background") {}
                .confirmationDialog("Dialog", isPresented: .constant(true)) { Button("Dialog action") {} }
        )

        for (result, tag) in [
            (sheet, "sheet-overlay"),
            (fullScreen, "full-screen-cover-overlay"),
            (popover, "popover-overlay"),
            (alert, "alert-overlay"),
            (dialog, "confirmation-dialog-overlay"),
        ] {
            guard let overlay = firstNode(in: result.node, matching: { $0.nodeTag == tag }) else {
                XCTFail("missing \(tag)")
                continue
            }
            XCTAssertTrue(overlay.accessibilityTraits.contains(.isModal), "\(tag) must isolate its modal content")
        }
    }

    func testBackgroundInteractiveSheetRemainsNonModal() async {
        let result = makeRuntime(
            Button("Background") {}
                .sheet(isPresented: .constant(true)) {
                    Button("Sheet action") {}
                        .presentationBackgroundInteraction(.enabled)
                }
        )
        guard let overlay = firstNode(in: result.node, matching: { $0.nodeTag == "sheet-overlay" }) else {
            return XCTFail("missing sheet overlay")
        }

        XCTAssertFalse(overlay.accessibilityTraits.contains(.isModal))
        let names = AccessibilityProjection.project(runtime: result.runtime)?.flattened().map(\.name) ?? []
        XCTAssertTrue(names.contains("Background"))
        XCTAssertTrue(names.contains("Sheet action"))
    }

    func testExplicitNonModalPresentationOverrideRemainsNonModal() async {
        let result = makeRuntime(
            Button("Background") {}
                .sheet(isPresented: .constant(true)) {
                    Button("Sheet action") {}
                        .presentationIsModal(false)
                }
        )
        guard let overlay = firstNode(in: result.node, matching: { $0.nodeTag == "sheet-overlay" }) else {
            return XCTFail("missing sheet overlay")
        }

        XCTAssertFalse(overlay.accessibilityTraits.contains(.isModal))
        let names = AccessibilityProjection.project(runtime: result.runtime)?.flattened().map(\.name) ?? []
        XCTAssertTrue(names.contains("Background"))
        XCTAssertTrue(names.contains("Sheet action"))
    }

    func testSheetDismissalReleasesModalScopeBeforeFocusRestoration() async {
        var isPresented = true
        let binding = Binding<Bool>(get: { isPresented }, set: { isPresented = $0 })
        let result = makeRuntime(
            Button("Background") {}
                .sheet(isPresented: binding) { Button("Dismiss") {} }
        )
        guard
            let background = firstNode(
                in: result.node.children[0], matching: { $0.accessibilityLabel == "Background" && $0.isFocusable }),
            let dismiss = firstNode(
                in: result.node.children[1], matching: { $0.accessibilityLabel == "Dismiss" && $0.isFocusable })
        else {
            return XCTFail("expected focusable base and presentation controls")
        }
        result.runtime.requestFocus(dismiss)

        let scrim = result.node.children[1].children[0]
        scrim.onActivate?()

        XCTAssertFalse(isPresented)
        XCTAssertTrue(result.runtime.focusedNode === background)
        XCTAssertFalse(result.node.children[1].accessibilityTraits.contains(.isModal))
    }

    func testCommandPaletteIsModalAndBlocksBackgroundSaveShortcut() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        model.displayName = "Unsaved operator"
        model.presentCommandPalette()
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model),
            size: Self.canvasSize,
            displayScale: 1,
            colorScheme: .dark
        )

        XCTAssertNotNil(firstNode(in: snapshot.runtime.root) { $0.isModalPresentationScope })

        snapshot.runtime.keyDown(KeyboardEvent(keyCode: 0x53, modifiers: [.control]))
        XCTAssertTrue(model.hasUnsavedSettings)
        XCTAssertNotEqual(model.lastAction, "Saved settings for Unsaved operator")

        let projection = AccessibilityProjection.project(runtime: snapshot.runtime)
        let names = projection?.flattened().map(\.name) ?? []
        XCTAssertTrue(names.contains("Search commands and actions"))
        XCTAssertFalse(names.contains("Save changes"))
        XCTAssertTrue(projection?.flattened().contains { $0.traits.contains(.isModal) } ?? false)
    }
}
