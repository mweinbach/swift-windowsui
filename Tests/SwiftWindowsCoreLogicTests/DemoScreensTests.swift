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

    // MARK: - G4-COMPOSE: demo composition

    private func absoluteX(of node: ViewNode) -> Double {
        var x = 0.0
        var current: ViewNode? = node
        while let candidate = current {
            x += candidate.resolvedFrame.origin.x
            current = candidate.parent
        }
        return x
    }

    /// The bottom edge of the lowest piece of text in the tree. Panels fill
    /// the window whether or not anything is in them, so the *text* is what
    /// says where a screen's content actually stops.
    private func lowestTextBottom(in root: ViewNode) -> Double {
        var lowest = 0.0
        var stack: [(node: ViewNode, y: Double)] = [(root, 0)]
        while let entry = stack.popLast() {
            let top = entry.y + entry.node.resolvedFrame.origin.y
            if let text = entry.node.text, !text.isEmpty {
                lowest = max(lowest, top + entry.node.resolvedFrame.size.height)
            }
            for child in entry.node.children {
                stack.append((child, top))
            }
        }
        return lowest
    }

    private func widestRoundedSurfaceWidth(in root: ViewNode) -> Double {
        var widest = 0.0
        var stack: [ViewNode] = [root]
        while let node = stack.popLast() {
            if node.cornerRadius > 0 {
                widest = max(widest, node.resolvedFrame.size.width)
            }
            stack.append(contentsOf: node.children)
        }
        return widest
    }

    /// G4 item 1. The data screen used to size its list at
    /// `proxy.size.height - 224` and then let the detail block measure
    /// whatever it measured. The detail block came in well under 224, so the
    /// screen ended in a bare strip of window about 75 pt tall. A greedy list
    /// takes exactly what its siblings leave, so the detail block lands on the
    /// bottom inset at every window size.
    func testDataScreenDetailBlockLandsOnTheBottomInset() async {
        let size = IntSize(width: 1280, height: 720)
        let model = DemoDashboardModel()
        model.selectedScreen = .data
        let root = laidOut(DemoRootView(model: model), size: size)

        let bottom = lowestTextBottom(in: root)
        XCTAssertGreaterThan(
            bottom, Double(size.height) - 44,
            "the detail block is pinned under a greedy list, so it ends on the screen's bottom inset")
        XCTAssertLessThanOrEqual(
            bottom, Double(size.height),
            "and it stays inside the window")
    }

    /// G4 item 2. The right rail reserved 8 pt of its own width for a scroll
    /// gutter. Overlay scrollers float over the content instead of taking
    /// layout space, so the reservation only pulled the rail's cards 8 pt
    /// short of the toolbar edge directly above them.
    func testRightRailCardsSpanTheFullRailWidth() async {
        let layout = DemoLayout(size: CGSize(width: 1280, height: 655))
        let model = DemoDashboardModel()
        let root = laidOut(
            DemoRightRail(model: model, layout: layout)
                .frame(width: layout.railWidth, height: 520, alignment: .topLeading),
            size: IntSize(width: 420, height: 560)
        )

        XCTAssertEqual(
            widestRoundedSurfaceWidth(in: root), layout.railWidth, accuracy: 0.5,
            "a rail card is as wide as the rail; there is no scroll gutter to reserve")
    }

    /// G4 item 3. A metric card's caption and a section eyebrow are the same
    /// kind of thing, so they sit on the same rung. The caption used to be
    /// `.tertiary`, which measured 1.86:1 against the light card fill — a
    /// shape rather than a word.
    func testCardCaptionsSitOnTheSecondaryRung() async {
        let root = laidOut(
            VStack(alignment: .leading, spacing: 12) {
                Text("Reference rung")
                    .foregroundStyle(.secondary)

                DemoMetricCard(
                    title: "Interactions", value: "0", note: "Events tracked", accent: Color.blue)

                DemoRowButton(
                    title: "State", detail: "Ready", systemImage: "info.circle", accent: Color.blue
                ) {}
            }
            .frame(width: 260),
            size: IntSize(width: 320, height: 420)
        )

        guard
            let reference = firstNode(in: root, matching: { $0.text == "Reference rung" }),
            let metricTitle = firstNode(in: root, matching: { $0.text == "Interactions" }),
            let rowDetail = firstNode(in: root, matching: { $0.text == "Ready" })
        else {
            return XCTFail("expected the reference rung, a metric title, and a row subtitle")
        }

        XCTAssertEqual(
            metricTitle.textStyle.color, reference.textStyle.color,
            "a metric card's caption reads at the same prominence as a section eyebrow")
        XCTAssertEqual(
            rowDetail.textStyle.color, reference.textStyle.color,
            "so does a row's subtitle")
    }

    /// G4 item 4. System Settings puts the noun in the label column and the
    /// value beside its stepper in the control column. The row used to fold
    /// the value into the label — "Items Per Page: 10" — which made it the one
    /// row in the pane whose label was a sentence.
    func testItemsPerPageRowKeepsTheValueOutOfTheLabel() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))

        XCTAssertNil(
            firstNode(in: root, matching: { ($0.text ?? "").hasPrefix("Items Per Page:") }),
            "the value does not live inside the label")

        guard
            let label = firstNode(in: root, matching: { $0.text == "Items Per Page" }),
            let value = firstNode(in: root, matching: { $0.text == "\(model.itemsPerPage)" })
        else {
            return XCTFail("expected a bare label and a separate value")
        }

        XCTAssertEqual(
            absoluteY(of: label), absoluteY(of: value), accuracy: 6,
            "label and value share the row's baseline")
        XCTAssertGreaterThan(
            absoluteX(of: value), absoluteX(of: label),
            "and the value is in the control column, to the right of the label column")
    }

    /// G4 item 5. Whether the three metric cards stack is a question about the
    /// content column's *width*. It used to ask `compact`, which is also true
    /// in a short window: the default 1280x720 window stacked the band,
    /// tripling its height in the window with the least height to spend, and
    /// the bottom of the scroll view came down across the middle of the
    /// third card.
    func testMetricBandStaysARowInAWideShortWindow() async {
        XCTAssertFalse(
            DemoLayout(size: CGSize(width: 1280, height: 720)).stacksMetrics,
            "a wide window keeps the band a row however short it is")
        XCTAssertTrue(
            DemoLayout(size: CGSize(width: 880, height: 900)).stacksMetrics,
            "a narrow one stacks it however tall it is")

        let model = DemoDashboardModel()
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))

        guard
            let interactions = firstNode(in: root, matching: { $0.text == "Interactions" }),
            let module = firstNode(in: root, matching: { $0.text == "Module" }),
            let target = firstNode(in: root, matching: { $0.text == "Target" })
        else {
            return XCTFail("expected the three metric captions")
        }

        XCTAssertEqual(absoluteY(of: interactions), absoluteY(of: module), accuracy: 2)
        XCTAssertEqual(absoluteY(of: module), absoluteY(of: target), accuracy: 2)
    }

    /// G4 item 5, the fold itself. The centre pane scrolls, so its bottom edge
    /// cuts the column somewhere; what it must not do is cut a card in half.
    /// The sidebar is framed at `layout.bodyHeight`, so its bottom edge *is*
    /// the centre pane's viewport bottom — the fold.
    func testDashboardFoldLandsInAGapNotAcrossACard() async {
        let model = DemoDashboardModel()
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))

        guard
            let workspace = firstNode(
                in: root,
                matching: { $0.text?.caseInsensitiveCompare("Workspace") == .orderedSame }),
            let sidebar = enclosingSurface(of: workspace),
            let moduleCaption = firstNode(in: root, matching: { $0.text == "Module" }),
            let moduleCard = enclosingSurface(of: moduleCaption)
        else {
            return XCTFail("expected a sidebar surface and a Module metric card")
        }

        let fold = absoluteY(of: sidebar) + sidebar.resolvedFrame.size.height
        let cardTop = absoluteY(of: moduleCard)
        let cardBottom = cardTop + moduleCard.resolvedFrame.size.height

        XCTAssertGreaterThan(fold, 0, "the sidebar is framed at the body height")
        XCTAssertFalse(
            cardTop < fold && cardBottom > fold,
            "the fold at \(fold) runs through the Module card (\(cardTop)...\(cardBottom))")
        XCTAssertLessThanOrEqual(
            cardBottom, fold,
            "and the band is fully above it, not pushed off the bottom entirely")
    }
}
