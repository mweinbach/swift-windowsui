import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Product-facing demo controls should exercise the retained stack rather
/// than presenting inert chrome or settings that never reach the view tree.
@MainActor
final class DemoInteractivePolishTests: XCTestCase {
    private func snapshotRoot(
        model: DemoDashboardModel,
        colorScheme: ColorScheme = .dark
    ) -> ViewNode {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model),
            size: IntSize(width: 1280, height: 720),
            displayScale: 1,
            colorScheme: colorScheme
        ).runtime.root
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
        firstNode(in: root) { $0.text == text }
    }

    func testThemeChoicesMapToRealColorSchemePreferences() async {
        XCTAssertNil(DemoThemeOption.system.colorScheme)
        XCTAssertEqual(DemoThemeOption.light.colorScheme, .light)
        XCTAssertEqual(DemoThemeOption.dark.colorScheme, .dark)
    }

    func testThemeSelectionChangesTheRenderedPageAndSystemKeepsTheAmbientAppearance() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings

        model.theme = .light
        let forcedLight = snapshotRoot(model: model, colorScheme: .dark)
        XCTAssertNotNil(
            firstNode(in: forcedLight) {
                $0.backgroundColor == DemoPalette(colorScheme: .light).base
                    && $0.resolvedFrame.size.width >= 700
            },
            "choosing Light should override a dark system appearance"
        )

        model.theme = .dark
        let forcedDark = snapshotRoot(model: model, colorScheme: .light)
        XCTAssertNotNil(
            firstNode(in: forcedDark) {
                $0.backgroundColor == DemoPalette(colorScheme: .dark).base
                    && $0.resolvedFrame.size.width >= 700
            },
            "choosing Dark should override a light system appearance"
        )

        model.theme = .system
        let systemLight = snapshotRoot(model: model, colorScheme: .light)
        XCTAssertNotNil(
            firstNode(in: systemLight) {
                $0.backgroundColor == DemoPalette(colorScheme: .light).base
                    && $0.resolvedFrame.size.width >= 700
            },
            "System must preserve the ambient appearance and screenshot overrides"
        )
    }

    func testAccentSelectionReachesTheStandardSwitchChrome() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        let selectedAccent = DemoPalette.hex(0x20_A3_5F)
        model.accentColor = selectedAccent

        XCTAssertNotNil(
            firstNode(in: snapshotRoot(model: model)) { $0.backgroundColor == selectedAccent },
            "an enabled switch should paint with the accent chosen in settings"
        )
    }

    func testResetRestoresAppearanceAccentAndFontScale() async {
        let model = DemoDashboardModel()
        model.theme = .dark
        model.accentColor = DemoPalette.hex(0x20_A3_5F)
        model.fontScale = 1.4

        model.resetSettings()

        XCTAssertEqual(model.theme, .system)
        XCTAssertEqual(model.accentColor, DemoSignature.accentFill)
        XCTAssertEqual(model.fontScale, 1)
        XCTAssertEqual(model.dynamicTypeSize, .large)
    }

    func testFontScaleMapsToStandardDynamicTypeSizes() async {
        let model = DemoDashboardModel()

        let expected: [(Double, DynamicTypeSize)] = [
            (0.8, .xSmall),
            (0.88, .small),
            (0.95, .medium),
            (1.0, .large),
            (1.12, .xLarge),
            (1.24, .xxLarge),
            (1.4, .xxxLarge),
        ]

        for (scale, size) in expected {
            model.fontScale = scale
            XCTAssertEqual(model.dynamicTypeSize, size, "unexpected size for \(scale)")
        }
    }

    func testFontScaleActuallyChangesRenderedTextSize() async {
        let model = DemoDashboardModel()
        let title = model.selectedModule.headline

        guard let baseline = textNode(in: snapshotRoot(model: model), title) else {
            return XCTFail("expected the dashboard headline at the default font scale")
        }
        let baselineSize = baseline.textStyle.nativeFontSize ?? 0

        model.fontScale = 1.4
        guard let enlarged = textNode(in: snapshotRoot(model: model), title) else {
            return XCTFail("expected the dashboard headline at the enlarged font scale")
        }

        XCTAssertEqual(baselineSize, 28, accuracy: 0.01)
        XCTAssertGreaterThan(enlarged.textStyle.nativeFontSize ?? 0, baselineSize)
    }

    func testComponentFilterSearchesNamesDetailsVersionsAndStatus() async {
        let model = DemoDashboardModel()

        model.componentFilter = "  D3D11   render  "
        XCTAssertEqual(model.filteredComponents.map(\.name), ["Render host"])

        model.componentFilter = "v3.1"
        XCTAssertEqual(model.filteredComponents.map(\.name), ["Layout engine"])

        model.componentFilter = "keyboard pointer"
        XCTAssertEqual(model.filteredComponents.map(\.name), ["Input router"])

        model.componentFilter = "DEGRADED"
        XCTAssertEqual(model.filteredComponents.map(\.name), ["System probe"])

        model.componentFilter = "  \t  "
        XCTAssertEqual(model.filteredComponents, model.components)
    }

    func testFilteringKeepsTheInspectorSelectionVisibleAndClearRestoresIt() async {
        let model = DemoDashboardModel()

        model.componentFilter = "router"
        XCTAssertEqual(model.selectedComponent?.name, "Input router")

        model.componentFilter = "no matching component exists"
        XCTAssertTrue(model.filteredComponents.isEmpty)
        XCTAssertNil(model.selectedComponent)

        model.clearComponentFilter()
        XCTAssertEqual(model.componentFilter, "")
        XCTAssertEqual(model.selectedComponentID, model.components.first?.id)
    }

    func testSelectFirstComponentHonorsTheCurrentFilter() async {
        let model = DemoDashboardModel()
        model.componentFilter = "animation"
        model.selectedComponentID = nil

        model.selectFirstComponent()

        XCTAssertEqual(model.selectedComponent?.name, "Animation ticker")
    }

    func testFilteredTableShowsOnlyMatchesAndAnAccurateCount() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .data
        model.componentFilter = "keyboard"

        let root = snapshotRoot(model: model)
        XCTAssertNotNil(textNode(in: root, "Input router"))
        XCTAssertNil(textNode(in: root, "Render host"))
        XCTAssertNotNil(textNode(in: root, "1 of 8 components"))
    }

    func testEmptyFilterResultsOfferAClearAction() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .data
        model.componentFilter = "unmatched component"

        let root = snapshotRoot(model: model)
        XCTAssertNotNil(textNode(in: root, "No matching components"))
        XCTAssertNotNil(textNode(in: root, "Clear filter"))
        XCTAssertNotNil(textNode(in: root, "0 of 8 components"))
        XCTAssertNil(model.selectedComponent)
    }

    func testComponentFilterIsFocusableAndEditsItsBinding() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .data

        guard
            let field = firstNode(
                in: snapshotRoot(model: model),
                matching: {
                    $0.accessibilityLabel == "Filter components" && $0.isFocusable
                })
        else {
            return XCTFail("the data filter must contain a real, focusable text input")
        }

        XCTAssertTrue(field.isHitTestVisible)
        field.onKeyDown?(KeyboardEvent(keyCode: 0x52))
        XCTAssertEqual(model.componentFilter, "r")
    }

    func testToolbarCommandSearchNavigatesModulesAndScreens() async {
        let model = DemoDashboardModel()

        model.commandQuery = "frame motion"
        model.runCommandSearch()
        XCTAssertEqual(model.selectedModule, .animation)
        XCTAssertEqual(model.commandQuery, "")

        model.commandQuery = "SETTINGS"
        model.runCommandSearch()
        XCTAssertEqual(model.selectedScreen, .settings)
        XCTAssertEqual(model.lastAction, "Opened Settings")
        XCTAssertEqual(model.commandQuery, "")
    }

    func testToolbarSearchIsFocusableAndSubmitRunsTheCommand() async {
        let model = DemoDashboardModel()
        model.commandQuery = "controls"

        guard
            let field = firstNode(
                in: snapshotRoot(model: model),
                matching: {
                    $0.accessibilityLabel == "Search commands" && $0.isFocusable
                })
        else {
            return XCTFail("the toolbar command field must accept real keyboard input")
        }

        field.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
        XCTAssertEqual(model.selectedModule, .controls)
        XCTAssertEqual(model.commandQuery, "")
    }
}
