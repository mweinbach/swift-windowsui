import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The component gallery is a real app destination, not dashboard-only chrome:
/// it remains discoverable by tab, command search, and a global shortcut.
@MainActor
final class DemoShowcaseNavigationTests: XCTestCase {
    private func snapshot(
        model: DemoDashboardModel,
        size: IntSize = IntSize(width: 1280, height: 720)
    ) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model),
            size: size,
            displayScale: 1,
            colorScheme: .dark
        )
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

    func testGalleryIsAppendedWithoutReorderingLegacyScreens() async {
        XCTAssertEqual(DemoScreen.allCases, [.dashboard, .settings, .data, .gallery])
        XCTAssertEqual(DemoScreen.gallery.label, "Gallery")
        XCTAssertEqual(DemoScreen.gallery.systemImage, "square.grid.2x2")
    }

    func testGalleryCommandIsDiscoverableWithoutShadowingControls() async {
        let model = DemoDashboardModel()

        for alias in ["gallery", "showcase", "catalog", "patterns", "examples"] {
            model.commandQuery = alias
            XCTAssertEqual(model.selectedCommand?.title, "Gallery", "missing gallery alias: \(alias)")
        }

        model.commandQuery = "controls"
        XCTAssertEqual(
            model.selectedCommand?.title,
            "Controls",
            "the established Controls module must keep its original command"
        )
    }

    func testExecutingGalleryCommandNavigatesAndRecordsOneEvent() async {
        let model = DemoDashboardModel()
        model.selectScreen(.settings)
        let initialInteractionCount = model.interactionCount
        model.presentCommandPalette()
        model.commandQuery = "showcase"

        model.runCommandSearch()

        XCTAssertEqual(model.selectedScreen, .gallery)
        XCTAssertEqual(model.lastAction, "Opened Gallery")
        XCTAssertEqual(model.interactionCount, initialInteractionCount + 1)
        XCTAssertFalse(model.isCommandPalettePresented)
        XCTAssertEqual(model.commandQuery, "")
    }

    func testGalleryTabIsVisibleAndActivatesFromTheDashboard() async {
        let model = DemoDashboardModel()
        let root = snapshot(model: model).runtime.root

        guard let label = firstNode(in: root, matching: { $0.text == "Gallery" }) else {
            return XCTFail("the dashboard tab bar must expose the Gallery destination")
        }

        var activatable: ViewNode? = label
        while activatable?.onActivate == nil {
            activatable = activatable?.parent
            if activatable == nil {
                break
            }
        }

        guard let galleryTab = activatable else {
            return XCTFail("the Gallery tab label must live inside an activatable control")
        }
        galleryTab.onActivate?()

        XCTAssertEqual(model.selectedScreen, .gallery)
        XCTAssertEqual(model.lastAction, "Opened Gallery")
    }

    func testGlobalGalleryShortcutSurvivesEveryScreenAndMinimumWindow() async {
        for screen in DemoScreen.allCases {
            let model = DemoDashboardModel()
            model.selectScreen(screen)
            let result = snapshot(model: model, size: IntSize(width: 640, height: 480))

            guard
                let target = firstNode(
                    in: result.runtime.root,
                    matching: {
                        $0.keyboardShortcuts.contains(
                            KeyboardShortcutBinding(keyCode: 0x47, modifiers: [.control])
                        )
                    })
            else {
                return XCTFail("\(screen) lost the global Ctrl+G gallery shortcut")
            }

            XCTAssertNotNil(target.onActivate)
            XCTAssertFalse(target.isFocusable, "a hidden global shortcut is not a traversal stop")
            XCTAssertTrue(target.isAccessibilityHidden, "shortcut plumbing is not an accessibility item")

            let interactionCount = model.interactionCount
            result.runtime.keyDown(KeyboardEvent(keyCode: 0x47, modifiers: []))
            XCTAssertEqual(model.selectedScreen, screen)
            XCTAssertEqual(model.interactionCount, interactionCount, "typing G is not a global command")

            result.runtime.keyDown(KeyboardEvent(keyCode: 0x47, modifiers: [.control]))
            XCTAssertEqual(model.selectedScreen, .gallery, "Ctrl+G should open the gallery from \(screen)")
        }
    }

    func testGalleryRendersAtTheSmallestSupportedWindowSize() async {
        let model = DemoDashboardModel()
        model.selectScreen(.gallery)
        let result = snapshot(model: model, size: IntSize(width: 640, height: 480))

        XCTAssertGreaterThan(result.scene.primitiveCount, 0)
        XCTAssertGreaterThan(result.frame.commands.count, 0)
        XCTAssertNotNil(firstNode(in: result.runtime.root, matching: { $0.text == "Gallery" }))
    }
}
