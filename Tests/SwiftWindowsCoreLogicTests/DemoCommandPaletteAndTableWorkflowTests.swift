import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Product workflows must remain useful when their toolbar disappears, when
/// the table spans pages, and when a settings change has not yet been saved.
@MainActor
final class DemoCommandPaletteAndTableWorkflowTests: XCTestCase {
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

    private func textNode(in root: ViewNode, _ text: String) -> ViewNode? {
        firstNode(in: root) { $0.text?.lowercased() == text.lowercased() }
    }

    private func absoluteY(of node: ViewNode) -> Double {
        var position = node.resolvedFrame.origin.y
        var parent = node.parent
        while let ancestor = parent {
            position += ancestor.resolvedFrame.origin.y
            parent = ancestor.parent
        }
        return position
    }

    func testGlobalCommandShortcutSurvivesEveryScreenAndMinimumWindow() async {
        for screen in DemoScreen.allCases {
            let model = DemoDashboardModel()
            model.selectedScreen = screen
            let result = snapshot(model: model, size: IntSize(width: 640, height: 480))

            guard
                let target = firstNode(
                    in: result.runtime.root,
                    matching: {
                        $0.keyboardShortcuts.contains(
                            KeyboardShortcutBinding(keyCode: 0x4B, modifiers: [.control])
                        )
                    })
            else {
                return XCTFail("\(screen) lost the global Ctrl+K command target")
            }

            XCTAssertNotNil(target.onActivate)
            XCTAssertFalse(target.isFocusable, "the hidden shortcut is not a keyboard traversal stop")
            XCTAssertTrue(target.isAccessibilityHidden, "an implementation detail is not an accessibility item")

            result.runtime.keyDown(KeyboardEvent(keyCode: 0x4B, modifiers: []))
            XCTAssertFalse(model.isCommandPalettePresented)

            result.runtime.keyDown(KeyboardEvent(keyCode: 0x4B, modifiers: [.control]))
            XCTAssertTrue(model.isCommandPalettePresented, "Ctrl+K should open on \(screen)")
        }
    }

    func testPresentedCommandPaletteContainsFocusedSearchResultsAndDismissControl() async {
        let model = DemoDashboardModel()
        model.presentCommandPalette()
        let root = snapshot(model: model, size: IntSize(width: 640, height: 480)).runtime.root

        XCTAssertNotNil(textNode(in: root, "Dashboard"))
        XCTAssertNotNil(textNode(in: root, "Settings"))
        XCTAssertNotNil(textNode(in: root, "Enter to run"))
        guard let escapeHint = textNode(in: root, "Esc to close") else {
            return XCTFail("the command surface should show its dismissal affordance")
        }
        XCTAssertLessThanOrEqual(
            absoluteY(of: escapeHint) + escapeHint.resolvedFrame.size.height,
            480,
            "the scrolling result list must leave its footer visible at the minimum window height"
        )

        XCTAssertNotNil(
            textNode(in: root, "Clear component filter"),
            "commands past the first viewport remain mounted and reachable by scrolling"
        )

        guard
            let search = firstNode(
                in: root,
                matching: {
                    $0.accessibilityLabel == "Search commands and actions" && $0.isFocusable
                })
        else {
            return XCTFail("the command palette should expose a real keyboard-focusable text field")
        }
        XCTAssertTrue(search.isHitTestVisible)

        XCTAssertNotNil(
            firstNode(in: root) { $0.accessibilityLabel == "Close command palette" && $0.onActivate != nil }
        )
    }

    func testCommandSearchMatchesScreenModuleQuickActionsAndUtilities() async {
        let model = DemoDashboardModel()

        model.commandQuery = "  frame   motion "
        XCTAssertEqual(model.selectedCommand?.title, "Animation")

        model.commandQuery = "read stacks"
        XCTAssertEqual(model.selectedCommand?.title, "Inspect Stacks")

        model.commandQuery = "restart health"
        XCTAssertEqual(model.selectedCommand?.title, "Restart selected component")

        model.commandQuery = "SETTINGS"
        XCTAssertEqual(model.selectedCommand?.title, "Settings", "navigation results stay ahead of utilities")

        model.commandQuery = "nothing matches this command"
        XCTAssertTrue(model.matchingCommands.isEmpty)
        XCTAssertNil(model.selectedCommand)
    }

    func testCommandSelectionClampsAndResetsWhenTheQueryChanges() async {
        let model = DemoDashboardModel()
        model.presentCommandPalette()

        model.moveCommandSelection(offset: 2)
        XCTAssertEqual(model.selectedCommandIndex, 2)

        model.moveCommandSelection(offset: -20)
        XCTAssertEqual(model.selectedCommandIndex, 0)

        model.moveCommandSelection(offset: 200)
        XCTAssertEqual(model.selectedCommandIndex, model.matchingCommands.count - 1)

        model.commandQuery = "system probe diagnostics"
        XCTAssertEqual(model.selectedCommandIndex, 0)
    }

    func testExecutingModuleAndQuickActionNavigatesAndDismissesPalette() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        model.presentCommandPalette()
        model.commandQuery = "frame motion"

        model.runCommandSearch()

        XCTAssertEqual(model.selectedScreen, .dashboard)
        XCTAssertEqual(model.selectedModule, .animation)
        XCTAssertFalse(model.isCommandPalettePresented)
        XCTAssertEqual(model.commandQuery, "")

        model.presentCommandPalette()
        model.commandQuery = "focus walk"
        model.runCommandSearch()

        XCTAssertEqual(model.selectedModule, .input)
        XCTAssertEqual(model.lastAction, "Focus walk started")
        XCTAssertFalse(model.isCommandPalettePresented)
    }

    func testPaletteEmptyStateAndEnterSubmitRouteTheSelectedCommand() async {
        let model = DemoDashboardModel()
        model.presentCommandPalette()
        model.commandQuery = "no such command exists"

        let empty = snapshot(model: model).runtime.root
        XCTAssertNotNil(textNode(in: empty, "No matching commands"))
        XCTAssertNotNil(textNode(in: empty, "Try a screen, module, or action"))

        model.commandQuery = "settings"
        let root = snapshot(model: model).runtime.root
        guard
            let field = firstNode(
                in: root,
                matching: {
                    $0.accessibilityLabel == "Search commands and actions" && $0.isFocusable
                })
        else {
            return XCTFail("the palette should expose its submit-enabled text field")
        }

        field.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
        XCTAssertEqual(model.selectedScreen, .settings)
        XCTAssertFalse(model.isCommandPalettePresented)
    }

    func testSidebarAndInspectorCommandsReflowWithoutLosingDashboardContent() async {
        let model = DemoDashboardModel()

        for size in [IntSize(width: 1280, height: 720), IntSize(width: 640, height: 480)] {
            let visible = snapshot(model: model, size: size).runtime.root
            let card = model.selectedModule.cards[1]
            guard
                let headline = textNode(in: visible, model.selectedModule.headline),
                let title = textNode(in: visible, card.title),
                let summary = textNode(in: visible, card.summary),
                let meta = textNode(in: visible, card.meta)
            else {
                return XCTFail("the hero and inspector typography should remain present at \(size)")
            }

            XCTAssertEqual(headline.textStyle.nativeFontSize ?? 0, 28, accuracy: 0.01)
            XCTAssertEqual(
                headline.textStyle.nativeLetterSpacing ?? 0,
                0.35,
                accuracy: 0.001,
                "display glyphs need breathing room without changing their pinned role"
            )
            XCTAssertEqual(
                title.textStyle.nativeLetterSpacing ?? 0,
                0.15,
                accuracy: 0.001,
                "semibold inspector titles should not collapse adjacent glyphs"
            )
            XCTAssertEqual(summary.textStyle.maximumNumberOfLines, 2)
            XCTAssertGreaterThan(summary.resolvedFrame.size.height, 0)
            XCTAssertGreaterThanOrEqual(
                absoluteY(of: meta),
                absoluteY(of: summary) + summary.resolvedFrame.size.height,
                "wrapped inspector copy and its metadata must never overlap at \(size)"
            )
        }

        model.commandQuery = "hide sidebar"
        model.runCommandSearch()
        XCTAssertTrue(model.isSidebarCollapsed)

        let collapsed = DemoLayout(
            size: WinSwiftUI.CGSize(width: 1280, height: 720),
            isSidebarCollapsed: model.isSidebarCollapsed,
            isInspectorCollapsed: model.isInspectorCollapsed
        )
        XCTAssertFalse(collapsed.showsSidebar)
        XCTAssertFalse(collapsed.showsRail)
        XCTAssertEqual(collapsed.contentWidth, 1280, accuracy: 0.001)

        let root = snapshot(model: model).runtime.root
        XCTAssertNotNil(textNode(in: root, "Layout"))
        XCTAssertNotNil(textNode(in: root, "Detail track"))

        model.commandQuery = "show sidebar"
        model.runCommandSearch()
        XCTAssertFalse(model.isSidebarCollapsed)

        model.commandQuery = "hide inspector"
        model.runCommandSearch()
        XCTAssertTrue(model.isInspectorCollapsed)

        let inspectorCollapsed = DemoLayout(
            size: WinSwiftUI.CGSize(width: 1280, height: 720),
            isSidebarCollapsed: model.isSidebarCollapsed,
            isInspectorCollapsed: model.isInspectorCollapsed
        )
        XCTAssertTrue(inspectorCollapsed.showsSidebar)
        XCTAssertFalse(inspectorCollapsed.showsRail)
    }

    func testColumnSortingPreservesDefaultOrderThenTogglesDirection() async {
        let model = DemoDashboardModel()
        XCTAssertEqual(model.filteredComponents, model.components)

        model.sortComponents(by: .name)
        XCTAssertEqual(model.componentSortColumn, .name)
        XCTAssertEqual(model.componentSortDirection, .ascending)
        XCTAssertEqual(model.displayedComponents.first?.name, "Animation ticker")
        XCTAssertEqual(model.displayedComponents.last?.name, "System probe")

        model.sortComponents(by: .name)
        XCTAssertEqual(model.componentSortDirection, .descending)
        XCTAssertEqual(model.displayedComponents.first?.name, "System probe")

        model.sortComponents(by: .load)
        XCTAssertEqual(model.componentSortDirection, .descending)
        XCTAssertEqual(model.displayedComponents.first?.name, "System probe")
        XCTAssertEqual(model.displayedComponents.last?.name, "Input router")

        model.sortComponents(by: .status)
        XCTAssertEqual(model.displayedComponents.first?.statusLabel, "Degraded")
        XCTAssertEqual(model.displayedComponents.dropFirst().map(\.id), Array(1...7))
    }

    func testVersionSortingComparesNumericSemanticSegments() async {
        let model = DemoDashboardModel()
        model.components = [
            DemoComponent(
                id: 1, name: "Ten", detail: "", version: "v10.0.0", systemImage: "bolt.fill", load: 0.1),
            DemoComponent(
                id: 2, name: "Two", detail: "", version: "v2.12.0", systemImage: "bolt.fill", load: 0.1),
            DemoComponent(
                id: 3, name: "One", detail: "", version: "v2.3.9", systemImage: "bolt.fill", load: 0.1),
        ]

        model.sortComponents(by: .version)

        XCTAssertEqual(model.displayedComponents.map(\.version), ["v2.3.9", "v2.12.0", "v10.0.0"])

        model.sortComponents(by: .version)
        XCTAssertEqual(model.displayedComponents.map(\.version), ["v10.0.0", "v2.12.0", "v2.3.9"])
    }

    func testSortingReturnsToFirstPageAndPreservesVisibleSelection() async {
        let model = DemoDashboardModel()
        model.itemsPerPage = 5
        model.selectNextComponentPage()
        XCTAssertEqual(model.componentPage, 1)

        model.sortComponents(by: .load)

        XCTAssertEqual(model.componentPage, 0)
        XCTAssertEqual(model.displayedComponents.count, 5)
        XCTAssertTrue(model.displayedComponents.contains { $0.id == model.selectedComponentID })
    }

    func testAdjacentSelectionCrossesPagesAndStopsAtDatasetEdges() async {
        let model = DemoDashboardModel()
        model.itemsPerPage = 5
        model.selectedComponentID = model.components[4].id

        model.selectAdjacentComponent(offset: 1)
        XCTAssertEqual(model.componentPage, 1)
        XCTAssertEqual(model.selectedComponentID, model.components[5].id)

        model.selectAdjacentComponent(offset: -1)
        XCTAssertEqual(model.componentPage, 0)
        XCTAssertEqual(model.selectedComponentID, model.components[4].id)

        model.selectAdjacentComponent(offset: -100)
        XCTAssertEqual(model.selectedComponentID, model.components.first?.id)

        model.selectAdjacentComponent(offset: 100)
        XCTAssertEqual(model.componentPage, 1)
        XCTAssertEqual(model.selectedComponentID, model.components.last?.id)
    }

    func testTableHeadersAreFocusableAndAnnounceSortDirection() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .data
        let root = snapshot(model: model).runtime.root

        guard
            let loadHeader = firstNode(
                in: root,
                matching: {
                    $0.accessibilityLabel == "Sort by Load" && $0.onActivate != nil
                })
        else {
            return XCTFail("Load should expose a focusable, actionable sortable header")
        }

        XCTAssertTrue(loadHeader.isFocusable)
        loadHeader.onActivate?()
        XCTAssertEqual(model.componentSortColumn, .load)
        XCTAssertEqual(model.componentSortDirection, .descending)

        let sorted = snapshot(model: model).runtime.root
        XCTAssertNotNil(
            firstNode(
                in: sorted,
                matching: {
                    $0.accessibilityLabel == "Sort by Load, currently descending"
                }))
    }

    func testCompactDataInspectorDropsMeterButPreservesBothActions() async {
        let narrowMetrics = DemoTableMetrics(width: 640)
        XCTAssertFalse(narrowMetrics.showsComponentCount)
        XCTAssertFalse(narrowMetrics.showsInspectorLoadMeter)
        XCTAssertEqual(narrowMetrics.filterFieldWidth, 180)

        let wideMetrics = DemoTableMetrics(width: 1280)
        XCTAssertTrue(wideMetrics.showsComponentCount)
        XCTAssertTrue(wideMetrics.showsInspectorLoadMeter)
        XCTAssertEqual(wideMetrics.filterFieldWidth, 240)

        let model = DemoDashboardModel()
        model.selectedScreen = .data
        let narrow = snapshot(model: model, size: IntSize(width: 640, height: 480)).runtime.root
        XCTAssertNil(textNode(in: narrow, "Current load"))
        XCTAssertNotNil(textNode(in: narrow, "Diagnose"))
        XCTAssertNotNil(textNode(in: narrow, "Restart"))
    }

    func testSettingsExposeSaveShortcutAndInlineValidation() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        model.displayName = "Keyboard operator"

        let editable = snapshot(model: model)
        XCTAssertNotNil(textNode(in: editable.runtime.root, "Unsaved changes"))
        XCTAssertNotNil(
            firstNode(in: editable.runtime.root) {
                $0.keyboardShortcuts.contains(
                    KeyboardShortcutBinding(keyCode: 0x53, modifiers: [.control])
                ) && $0.onActivate != nil
            },
            "the settings primary action should expose the standard Ctrl+S shortcut"
        )

        editable.runtime.keyDown(KeyboardEvent(keyCode: 0x53, modifiers: [.control]))
        XCTAssertEqual(model.lastAction, "Saved settings for Keyboard operator")
        XCTAssertFalse(model.hasUnsavedSettings)

        model.displayName = "    "
        let invalid = snapshot(model: model).runtime.root
        XCTAssertNotNil(textNode(in: invalid, "Enter a display name before saving"))
    }

    func testSettingsReportDirtySavedInvalidAndResetStates() async {
        let model = DemoDashboardModel()

        XCTAssertFalse(model.hasUnsavedSettings)
        XCTAssertEqual(model.settingsStatusMessage, "Configure the demo shell")

        model.displayName = "New operator"
        XCTAssertTrue(model.hasUnsavedSettings)
        XCTAssertEqual(model.settingsStatusMessage, "Unsaved changes")

        model.saveSettings()
        XCTAssertFalse(model.hasUnsavedSettings)
        XCTAssertTrue(model.hasSavedSettings)
        XCTAssertEqual(model.settingsStatusMessage, "All changes saved")

        model.displayName = "   \t"
        XCTAssertFalse(model.isDisplayNameValid)
        model.saveSettings()
        XCTAssertEqual(model.lastAction, "Enter a display name before saving")
        XCTAssertTrue(model.hasUnsavedSettings)

        model.resetSettings()
        XCTAssertEqual(model.displayName, "Operator")
        XCTAssertTrue(model.hasUnsavedSettings, "resetting away from a saved custom profile is a new edit")
    }
}
