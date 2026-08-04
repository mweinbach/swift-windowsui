import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

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

    // MARK: - Demo-authored layout

    /// Builds and lays out a demo view through the same headless path the
    /// screenshot tool takes, and hands back the laid-out root so a test can
    /// read real frames off it.
    private func laidOut<V: View>(_ view: V, size: IntSize) -> ViewNode {
        WinSwiftUIRendererSnapshotter.snapshot(of: view, size: size, displayScale: 1).runtime.root
    }

    private func firstNode(in node: ViewNode, matching predicate: (ViewNode) -> Bool) -> ViewNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let hit = firstNode(in: child, matching: predicate) { return hit }
        }
        return nil
    }

    /// The surface a piece of text is drawn on: the nearest rounded ancestor.
    /// For the demo's cards and rows, that is the card.
    private func enclosingSurface(of node: ViewNode) -> ViewNode? {
        var current = node.parent
        while let candidate = current {
            if candidate.cornerRadius > 0 { return candidate }
            current = candidate.parent
        }
        return nil
    }

    private func absoluteY(of node: ViewNode) -> Double {
        var y = 0.0
        var current: ViewNode? = node
        while let candidate = current {
            y += candidate.resolvedFrame.origin.y
            current = candidate.parent
        }
        return y
    }

    /// P-DEMO item 2. Every data-screen row used to carry a two-line trailing
    /// block — version stacked over status — which made the row a ~42 pt box
    /// once the list's own insets were added. A macOS list row is one line.
    func testComponentRowIsOneLineTall() async {
        let first = DemoComponent.defaults[0]
        let second = DemoComponent.defaults[1]
        let node = laidOut(
            VStack(alignment: .leading, spacing: 0) {
                DemoComponentRow(component: first)
                DemoComponentRow(component: second)
            },
            size: IntSize(width: 480, height: 400)
        )

        guard
            let firstName = firstNode(in: node, matching: { $0.text == first.name }),
            let secondName = firstNode(in: node, matching: { $0.text == second.name })
        else {
            return XCTFail("expected both component names to be laid out")
        }

        let pitch = absoluteY(of: secondName) - absoluteY(of: firstName)
        XCTAssertGreaterThan(pitch, 10, "the rows are stacked, so the pitch is the first row's height")
        XCTAssertLessThan(
            pitch, 28,
            "a one-line row; the stacked version-over-status block made this a two-line box")
    }

    /// P-DEMO item 2, the structural half: the version and the status badge
    /// share one line, so they sit on one baseline rather than stacking.
    func testComponentRowPutsVersionAndStatusOnOneLine() async {
        let component = DemoComponent.defaults[0]
        let node = laidOut(
            DemoComponentRow(component: component), size: IntSize(width: 480, height: 120))

        guard
            let version = firstNode(in: node, matching: { $0.text == component.version }),
            let status = firstNode(in: node, matching: { $0.text == component.statusLabel })
        else {
            return XCTFail("expected the row to carry a version and a status label")
        }

        XCTAssertEqual(
            version.resolvedFrame.origin.y, status.resolvedFrame.origin.y, accuracy: 4,
            "version and status are one line, not a stacked trailing block")
    }

    /// P-DEMO item 4. Sibling cards in the right rail are as wide as the rail,
    /// not as wide as their own longest line — the rail used to read as a pile
    /// of differently sized boxes with a ragged right edge.
    func testDetailTrackCardsShareTheColumnWidth() async {
        let cards = DemoModule.layout.cards
        XCTAssertGreaterThanOrEqual(cards.count, 2)

        let columnWidth = 240.0
        let node = laidOut(
            VStack(alignment: .leading, spacing: 14) {
                DemoInfoCard(card: cards[0], module: .layout)
                DemoInfoCard(card: cards[1], module: .layout)
            }
            .frame(width: columnWidth),
            size: IntSize(width: 400, height: 500)
        )

        let widths = cards.prefix(2).compactMap { card -> Double? in
            guard
                let title = firstNode(in: node, matching: { $0.text == card.title }),
                let surface = enclosingSurface(of: title)
            else { return nil }
            return surface.resolvedFrame.size.width
        }

        XCTAssertEqual(widths.count, 2, "expected both cards to draw a rounded surface")
        XCTAssertEqual(
            widths[0], widths[1], accuracy: 0.5,
            "two cards in one column are one width")
        XCTAssertGreaterThan(
            widths[0], columnWidth - 40,
            "and that width is the column's, not the longest line's")
    }
}
