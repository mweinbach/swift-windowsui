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
                DemoInfoCard(card: cards[0])
                DemoInfoCard(card: cards[1])
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

    /// G4 item 3 + FINAL item 4. A metric card's caption and a section
    /// eyebrow are the same kind of thing, so they sit on the same rung. The
    /// caption used to be `.tertiary`, which measured 1.86:1 against the
    /// light card fill — a shape rather than a word. The card's *note* is a
    /// caption too: it used to take a per-module accent, so "Events tracked"
    /// sat in link blue next to "Import WinSwiftUI or SwiftUI" in slate. One
    /// rule — captions are `.secondary`; an accent means interactive.
    func testCardCaptionsSitOnTheSecondaryRung() async {
        let root = laidOut(
            VStack(alignment: .leading, spacing: 12) {
                Text("Reference rung")
                    .foregroundStyle(.secondary)

                DemoMetricCard(
                    title: "Interactions", value: "0", note: "Events tracked")

                DemoRowButton(
                    title: "State", detail: "Ready", systemImage: "info.circle",
                    accent: DemoModule.layout.accentFill
                ) {}

                DemoInfoCard(card: DemoModule.layout.cards[0])
            }
            .frame(width: 260),
            size: IntSize(width: 320, height: 500)
        )

        guard
            let reference = firstNode(in: root, matching: { $0.text == "Reference rung" }),
            let metricTitle = firstNode(in: root, matching: { $0.text == "Interactions" }),
            let metricNote = firstNode(in: root, matching: { $0.text == "Events tracked" }),
            let rowDetail = firstNode(in: root, matching: { $0.text == "Ready" }),
            let cardMeta = firstNode(
                in: root, matching: { $0.text == DemoModule.layout.cards[0].meta })
        else {
            return XCTFail("expected the reference rung and all four caption kinds")
        }

        XCTAssertEqual(
            metricTitle.textStyle.color, reference.textStyle.color,
            "a metric card's caption reads at the same prominence as a section eyebrow")
        XCTAssertEqual(
            metricNote.textStyle.color, reference.textStyle.color,
            "and so does its note — the accent is reserved for interactive text")
        XCTAssertEqual(
            rowDetail.textStyle.color, reference.textStyle.color,
            "so does a row's subtitle")
        XCTAssertEqual(
            cardMeta.textStyle.color, reference.textStyle.color,
            "and an info card's meta line")
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
        // L7-ADAPT moved the subject of "narrow" from the window to the
        // column: at 880 pt the detail rail now folds away and the centre
        // column gets 610 pt, which is a row. A 1000 pt window still carries
        // all three columns, so its centre column is 456 pt — that is what a
        // narrow *column* looks like now, and it stacks however tall the
        // window is.
        XCTAssertTrue(
            DemoLayout(size: CGSize(width: 1000, height: 900)).stacksMetrics,
            "a narrow column stacks the band however tall the window is")
        XCTAssertFalse(
            DemoLayout(size: CGSize(width: 880, height: 900)).stacksMetrics,
            "and a window that gave up its rail has a column wide enough for the row")

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

    // MARK: - G5-COMPOSE: demo composition

    /// The fill a piece of text is drawn on: the nearest ancestor carrying a
    /// non-transparent background. A demo surface draws its fill and its
    /// corner on two different nodes, so "the nearest rounded ancestor" and
    /// "the nearest filled ancestor" are not the same node.
    private func nearestFill(above node: ViewNode) -> Color? {
        var current = node.parent
        while let candidate = current {
            if let fill = candidate.backgroundColor, fill.alpha > 0 { return fill }
            current = candidate.parent
        }
        return nil
    }

    private func relativeLuminance(of color: Color) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(Double(color.red)) + 0.7152 * channel(Double(color.green))
            + 0.0722 * channel(Double(color.blue))
    }

    /// WCAG contrast of `text` drawn at its own alpha over an *opaque* `fill`.
    private func contrastRatio(text: Color, over fill: Color) -> Double {
        let alpha = Double(text.alpha)
        let red: Double = alpha * Double(text.red) + (1 - alpha) * Double(fill.red)
        let green: Double = alpha * Double(text.green) + (1 - alpha) * Double(fill.green)
        let blue: Double = alpha * Double(text.blue) + (1 - alpha) * Double(fill.blue)
        let composited = Color(
            red: Float(red), green: Float(green), blue: Float(blue), alpha: 1)
        let a = relativeLuminance(of: composited)
        let b = relativeLuminance(of: fill)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// G5 item 1. The demo writes a near-white label on every fill it tints
    /// itself, so those fills have to be colours rather than washes of one.
    ///
    /// They used to be `glowColor`/`stripeColor` — pale hues carrying alpha,
    /// meant to be laid *over* something. Composited onto a light window the
    /// "Open Layout" pill resolved to #88BDF2 and its label measured 1.9:1;
    /// on the dark window the same pill only reached 2.4:1. An opaque fill
    /// has no appearance to vary with, which is why one ramp answers for
    /// both.
    func testEveryTintedFillCarriesItsNearWhiteLabelAtFourPointFive() async {
        let label = DemoTheme(colorScheme: .light).onTintedFillText
        XCTAssertEqual(
            label, DemoTheme(colorScheme: .dark).onTintedFillText,
            "one label colour on tinted fills, in both appearances")

        var ramps: [(name: String, colors: [Color])] = [
            ("ready", DemoTheme.readyFill),
            ("events", DemoTheme.eventsFill),
        ]
        for module in DemoModule.allCases {
            ramps.append((String(describing: module), module.accentFill))
        }

        for ramp in ramps {
            for (index, stop) in ramp.colors.enumerated() {
                XCTAssertEqual(
                    stop.alpha, 1, accuracy: 0.001,
                    "\(ramp.name) stop \(index) is a wash, not a fill")
                let ratio = contrastRatio(text: label, over: stop)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "\(ramp.name) stop \(index) measures \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    /// The same for the hero card's tinted badge, which takes its fill from a
    /// caller and used to knock it back to 0.92 on the way in.
    func testTintedBadgeKeepsItsFillOpaque() async {
        let model = DemoDashboardModel()
        for scheme in [ColorScheme.light, ColorScheme.dark] {
            let root = laidOut(
                DemoCapsuleText(model.selectedModule.label, tint: model.selectedModule.fillTop)
                    .environment(\.colorScheme, scheme),
                size: IntSize(width: 200, height: 80)
            )
            guard
                let text = firstNode(in: root, matching: { $0.text == model.selectedModule.label }),
                let fill = nearestFill(above: text)
            else {
                return XCTFail("expected a badge surface with a fill in \(scheme)")
            }
            XCTAssertEqual(fill.alpha, 1, accuracy: 0.001, "a badge fill is a fill")
            XCTAssertGreaterThanOrEqual(
                contrastRatio(text: DemoTheme(colorScheme: scheme).onTintedFillText, over: fill),
                4.5)
        }
    }

    /// G5 item 2. `.navigationTitle` is drawn by the pane's chrome at the
    /// pane's own leading edge, so in a 1280pt window "Settings" sat 320pt
    /// away from the 640pt column it was titling, with nothing under it in
    /// between. The title belongs on the column.
    func testSettingsTitleSitsOnTheContentColumn() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))

        guard
            let title = firstNode(
                in: root,
                matching: { $0.text == "Settings" && ($0.textStyle.nativeFontSize ?? 0) > 20 }),
            let sectionHeader = firstNode(in: root, matching: { $0.text == "Profile" })
        else {
            return XCTFail("expected a large pane title and a section header")
        }

        XCTAssertEqual(
            absoluteX(of: title), absoluteX(of: sectionHeader), accuracy: 8,
            "the title leads on the same edge as the section headers under it")
        XCTAssertGreaterThan(
            absoluteX(of: title), 200,
            "and it is inside the centred column, not at the window's edge")
    }

    /// G5 item 3 + FINAL item 2. The inspector used to be a paragraph after
    /// the list, split from it by a hairline in a 12pt gap — both standing on
    /// the same window background, so the block read as floating text. macOS
    /// closes an inspector with a *bar*: its own scrim, a rule along its top
    /// edge. What the scrim is differs by appearance: a dark-mode bar is
    /// *lighter* than the window (the white quaternary rung), but a light
    /// bottom bar is never darker than the window it closes — Finder's status
    /// bar sits at the window tone and lets the divider do the work. The
    /// light `.quaternary` background used to composite the black label rung
    /// to #D5D5D5 on the #ECECEC window, and the bar's four secondary strings
    /// measured 4.28:1.
    func testDataInspectorSitsOnABarRatherThanTheWindow() async {
        for scheme in [ColorScheme.light, ColorScheme.dark] {
            let model = DemoDashboardModel()
            model.selectedScreen = .data
            let root = laidOut(
                DemoRootView(model: model).environment(\.colorScheme, scheme),
                size: IntSize(width: 1280, height: 720))

            guard let load = firstNode(in: root, matching: { $0.text == "Current load" }) else {
                return XCTFail("expected the inspector's load caption in \(scheme)")
            }

            var bar: ViewNode?
            var current = load.parent
            while let candidate = current {
                if let fill = candidate.backgroundColor, fill.alpha > 0,
                    candidate.resolvedFrame.size.width > 1000
                {
                    bar = candidate
                    break
                }
                current = candidate.parent
            }

            guard let bar, let fill = bar.backgroundColor else {
                return XCTFail("the inspector has no bar behind it in \(scheme)")
            }

            if scheme == .light {
                let palette = ControlPalette.lightStandard
                XCTAssertEqual(
                    fill, palette.windowBackground,
                    "a light bottom bar sits at the window tone, not below it")
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(text: palette.secondaryLabel, over: fill), 4.5,
                    "the bar's secondary strings clear WCAG AA on the bar tone")
            } else {
                // The white quaternary rung: a translucent scrim that
                // *lightens* the dark window into a bar.
                XCTAssertGreaterThan(Double(fill.red), 0.5, "a dark bar scrim is white-based")
                XCTAssertEqual(
                    fill.alpha, LabelHierarchy.quaternaryAlpha, accuracy: 0.001,
                    "and it is the quaternary rung, unchanged")
            }
        }
    }

    /// FINAL item 6. The settings pane's rhythm decides where the default
    /// window's scroll fold lands. It has to land in the *gap* between the
    /// "Resources" box and the "Actions" header: at the old 24/22 rhythm the
    /// header sat fully visible just above the fold with its box below it —
    /// an orphaned eyebrow captioning the bottom edge of the window.
    func testSettingsFoldLandsBetweenResourcesAndActions() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))

        guard
            let syncButton = firstNode(in: root, matching: { $0.text == "Sync Now" }),
            let resourcesBox = enclosingSurface(of: syncButton),
            let actionsHeader = firstNode(in: root, matching: { $0.text == "Actions" })
        else {
            return XCTFail("expected the Resources box and the Actions header")
        }

        let fold = 720.0
        let boxBottom = absoluteY(of: resourcesBox) + resourcesBox.resolvedFrame.size.height
        XCTAssertLessThan(boxBottom, fold, "the Resources box closes above the fold")
        XCTAssertGreaterThan(
            absoluteY(of: actionsHeader), fold,
            "and the Actions header opens below it — never orphaned on the fold line")
    }

    /// FINAL item 1. The Degraded status carries its orange on a *symbol*
    /// and keeps the word `.secondary`: bare `.orange` 10pt text composites
    /// to 2.2:1 on the white list. The nominal rows stay undecorated, the
    /// way Activity Monitor leaves them.
    func testDegradedStatusIsADotBesideSecondaryText() async {
        let degraded = DemoComponent.defaults.first { !$0.isHealthy }
        let healthy = DemoComponent.defaults.first { $0.isHealthy }
        guard let degraded, let healthy else {
            return XCTFail("the fixture data carries both states")
        }

        let root = laidOut(
            VStack(alignment: .leading, spacing: 0) {
                Text("Reference rung").foregroundStyle(.secondary)
                DemoComponentRow(component: degraded)
                DemoComponentRow(component: healthy)
            },
            size: IntSize(width: 480, height: 200)
        )

        guard
            let reference = firstNode(in: root, matching: { $0.text == "Reference rung" }),
            let degradedWord = firstNode(in: root, matching: { $0.text == degraded.statusLabel }),
            let healthyWord = firstNode(in: root, matching: { $0.text == healthy.statusLabel })
        else {
            return XCTFail("expected both status words")
        }

        XCTAssertEqual(
            degradedWord.textStyle.color, reference.textStyle.color,
            "the word is legible text, not an accent swatch")
        XCTAssertEqual(healthyWord.textStyle.color, reference.textStyle.color)

        // The orange lives on the dot — a small filled shape on the degraded
        // row only.
        var dot: ViewNode?
        var stack: [ViewNode] = [root]
        while let node = stack.popLast() {
            if let fill = node.backgroundColor, fill.red > 0.9, fill.green > 0.4, fill.green < 0.75,
                fill.blue < 0.2, node.resolvedFrame.size.width <= 8
            {
                dot = node
                break
            }
            stack.append(contentsOf: node.children)
        }
        XCTAssertNotNil(dot, "the degraded row carries an orange status dot")
    }

    /// G5 item 4a, strengthened by L7-ADAPT. The hero card's two pills used to
    /// stack below 1180 pt of window while the card's height stayed flat, so
    /// the fixed-height card answered the overflow by squeezing them — 28 pt
    /// at 900, 0.9 pt at 640. The stacking branch is gone: the centre column
    /// now has an enforced 420 pt floor, which always has room for the row.
    /// So the claim is no longer "a wide window keeps them a row", it is
    /// "every window does".
    func testHeroActionsStayARowAtEveryReachableWindowSize() async {
        let model = DemoDashboardModel()

        for size in [
            IntSize(width: 640, height: 480),
            IntSize(width: 640, height: 720),
            IntSize(width: 900, height: 600),
            IntSize(width: 1000, height: 900),
            IntSize(width: 1280, height: 720),
            IntSize(width: 1720, height: 980),
        ] {
            let root = laidOut(DemoRootView(model: model), size: size)

            guard
                let open = firstNode(in: root, matching: { $0.text == "Open Layout" }),
                let cycle = firstNode(in: root, matching: { $0.text == "Cycle mode" }),
                let openPill = enclosingSurface(of: open)
            else {
                return XCTFail("expected both hero pills at \(size.width)x\(size.height)")
            }

            XCTAssertEqual(
                absoluteY(of: open), absoluteY(of: cycle), accuracy: 2,
                "one row at \(size.width)x\(size.height)")
            XCTAssertGreaterThanOrEqual(
                openPill.resolvedFrame.size.height, 34,
                "at \(size.width)x\(size.height) a pill is as tall as it asked to be, "
                    + "not squeezed by an overflowing card")
        }
    }

    /// G5 item 4b. The right rail is two panels in the height the centre pane
    /// spends on one, so it carries a tighter internal rhythm. At the centre
    /// column's rhythm it ran ~30pt past the bottom of its scroll view and
    /// the fold went through the middle of the "Resize Panes" row.
    func testRightRailFitsAboveTheFold() async {
        let model = DemoDashboardModel()
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))

        guard
            let workspace = firstNode(
                in: root,
                matching: { $0.text?.caseInsensitiveCompare("Workspace") == .orderedSame }),
            let sidebar = enclosingSurface(of: workspace),
            let resize = firstNode(in: root, matching: { $0.text == "Resize Panes" }),
            let resizeRow = enclosingSurface(of: resize)
        else {
            return XCTFail("expected a sidebar surface and the last quick-action row")
        }

        let fold = absoluteY(of: sidebar) + sidebar.resolvedFrame.size.height
        let rowTop = absoluteY(of: resizeRow)
        let rowBottom = rowTop + resizeRow.resolvedFrame.size.height

        XCTAssertFalse(
            rowTop < fold && rowBottom > fold,
            "the fold at \(fold) runs through the Resize Panes row (\(rowTop)...\(rowBottom))")
        XCTAssertLessThanOrEqual(rowBottom, fold, "the rail's last row is whole and above the fold")
    }
}
