import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSwiftUI
import XCTest

@testable import SwiftWindowsDemo

/// Smoke tests for the multi-screen product demo in `SwiftWindowsDemo`.
/// Each screen is snapshotted headlessly through the same
/// `WinSwiftUIRendererSnapshotter` path used by `swift-windowsui-snapshot`.
@MainActor
final class DemoScreensTests: XCTestCase {

    private func snapshotScreen(
        _ screen: DemoScreen,
        size: IntSize = IntSize(width: 1280, height: 720)
    ) -> WinSwiftUIRenderSnapshot {
        let model = DemoDashboardModel()
        model.selectedScreen = screen
        return WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model),
            size: size,
            displayScale: 1
        )
    }

    func testDashboardScreenRenders() async {
        let snapshot = snapshotScreen(.dashboard)
        XCTAssertGreaterThan(snapshot.scene.primitiveCount, 0)
        XCTAssertGreaterThan(snapshot.frame.commands.count, 0)
    }

    func testSettingsScreenRenders() async {
        let snapshot = snapshotScreen(.settings)
        XCTAssertGreaterThan(snapshot.scene.primitiveCount, 0)
        XCTAssertGreaterThan(snapshot.frame.commands.count, 0)
    }

    func testDataScreenRenders() async {
        let snapshot = snapshotScreen(.data)
        XCTAssertGreaterThan(snapshot.scene.primitiveCount, 0)
        XCTAssertGreaterThan(snapshot.frame.commands.count, 0)
    }

    func testCompactSizeScreensRender() async {
        let compact = IntSize(width: 800, height: 600)
        for screen in DemoScreen.allCases {
            let snapshot = snapshotScreen(screen, size: compact)
            XCTAssertGreaterThan(snapshot.scene.primitiveCount, 0, "screen \(screen) produced no primitives")
        }
    }

    func testTabSelectionRecordsEvent() async {
        let model = DemoDashboardModel()
        XCTAssertEqual(model.selectedScreen, .dashboard)

        model.selectedScreen = .settings
        XCTAssertEqual(model.selectedScreen, .settings)
        XCTAssertEqual(model.lastAction, "Opened Settings")

        model.selectedScreen = .data
        XCTAssertEqual(model.lastAction, "Opened Data")
    }

    func testDataScreenSelectionDefaultsToFirstComponent() async {
        let model = DemoDashboardModel()
        XCTAssertFalse(model.components.isEmpty)
        XCTAssertEqual(model.selectedComponentID, model.components.first?.id)
        XCTAssertNotNil(model.selectedComponent)

        model.selectedComponentID = nil
        XCTAssertNil(model.selectedComponent)

        model.selectFirstComponent()
        XCTAssertEqual(model.selectedComponentID, model.components.first?.id)
    }
}
