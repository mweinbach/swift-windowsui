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

    // MARK: - Helpers

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

    private func allNodes(in root: ViewNode, matching predicate: (ViewNode) -> Bool) -> [ViewNode] {
        var found: [ViewNode] = []
        var stack: [ViewNode] = [root]
        while let node = stack.popLast() {
            if predicate(node) { found.append(node) }
            stack.append(contentsOf: node.children)
        }
        return found
    }

    /// Text nodes are matched case-insensitively throughout: an eyebrow is
    /// written sentence-case in source and uppercased by `.textCase`, so the
    /// tree may carry either spelling.
    private func textNode(in root: ViewNode, _ text: String) -> ViewNode? {
        firstNode(in: root, matching: { $0.text?.caseInsensitiveCompare(text) == .orderedSame })
    }

    /// The surface a piece of text is drawn on: the nearest rounded ancestor.
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

    private func absoluteX(of node: ViewNode) -> Double {
        var x = 0.0
        var current: ViewNode? = node
        while let candidate = current {
            x += candidate.resolvedFrame.origin.x
            current = candidate.parent
        }
        return x
    }

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

    /// The same, for a surface filled with a gradient: a quad resolves a
    /// gradient from its first stop, so that stop is the fill.
    private func nearestGradientStart(above node: ViewNode) -> Color? {
        var current = node.parent
        while let candidate = current {
            if let gradient = candidate.backgroundGradient { return gradient.startColor }
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

    private func chroma(of color: Color) -> Float {
        max(color.red, max(color.green, color.blue)) - min(color.red, min(color.green, color.blue))
    }

    // MARK: - The design system reaches the demo

    /// The demo is same-source with macOS SwiftUI, so it cannot import
    /// `ControlPalette`; it carries a portable mirror of the ramp instead.
    /// This is what stops the mirror becoming a second design system: every
    /// token the demo paints with is asserted against the role the stack
    /// resolves for the same appearance, so a value changed in one place and
    /// not the other fails here rather than in a screenshot three weeks later.
    func testDemoPaletteMirrorsTheStackPalette() async {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let demo = DemoPalette(colorScheme: scheme)
            let stack = ControlPalette.resolve(colorScheme: scheme)

            XCTAssertEqual(demo.base, stack.base, "\(scheme) base")
            XCTAssertEqual(demo.surface0, stack.surface0, "\(scheme) surface0")
            XCTAssertEqual(demo.surface1, stack.surface1, "\(scheme) surface1")
            XCTAssertEqual(demo.surface2, stack.surface2, "\(scheme) surface2")
            XCTAssertEqual(demo.surface3, stack.surface3, "\(scheme) surface3")
            XCTAssertEqual(
                demo.pageItemHover, stack.pageItemHoverFill, "\(scheme) page item hover")

            XCTAssertEqual(demo.strokeSubtle, stack.separator, "\(scheme) strokeSubtle")
            XCTAssertEqual(demo.stroke, stack.controlBorder, "\(scheme) stroke")
            XCTAssertEqual(demo.strokeStrong, stack.controlBorderStrong, "\(scheme) strokeStrong")
            XCTAssertEqual(demo.edgeHighlight, stack.raisedSurfaceHighlight, "\(scheme) edgeHighlight")

            XCTAssertEqual(demo.accentInk, stack.accentForeground, "\(scheme) accent ink")
            XCTAssertEqual(demo.accentFill, stack.accentFill, "\(scheme) accent fill")
            XCTAssertEqual(
                demo.accentFillHovered, stack.accentFillHovered, "\(scheme) accent fill hovered")
            XCTAssertEqual(
                demo.accentFillPressed, stack.accentFillPressed, "\(scheme) accent fill pressed")
            XCTAssertEqual(demo.accentWash, stack.accentWash, "\(scheme) accent wash")
            XCTAssertEqual(demo.accentWashStrong, stack.accentWashStrong, "\(scheme) accent wash strong")

            XCTAssertEqual(demo.success, stack.success, "\(scheme) success")
            XCTAssertEqual(demo.warning, stack.warning, "\(scheme) warning")
            XCTAssertEqual(demo.danger, stack.danger, "\(scheme) danger")
            XCTAssertEqual(
                demo.statusWash(demo.warning), stack.statusWash(stack.warning), "\(scheme) status wash")

            XCTAssertEqual(
                demo.cardShadow, stack.groupedContainerShadow, "\(scheme) card shadow")
            XCTAssertEqual(
                demo.cardShadowRadius, MacOSControlMetrics.GroupBox.shadowSpread, accuracy: 0.001,
                "\(scheme) card shadow radius")
            XCTAssertEqual(
                demo.cardShadowOffsetY, MacOSControlMetrics.GroupBox.shadowOffsetY, accuracy: 0.001,
                "\(scheme) card shadow offset")
            XCTAssertEqual(demo.heroShadow, Elevation.e4.color(for: scheme), "\(scheme) hero shadow")
            XCTAssertEqual(
                demo.heroShadowRadius, Elevation.e4.radius(for: scheme), accuracy: 0.001,
                "\(scheme) hero shadow radius")
        }
    }

    /// And the geometry scales: the demo may only spend steps the system has.
    func testDemoMetricsMirrorTheStackScales() async {
        XCTAssertEqual(DemoMetrics.s1, MacOSControlMetrics.Spacing.s1, accuracy: 0.001)
        XCTAssertEqual(DemoMetrics.s2, MacOSControlMetrics.Spacing.s2, accuracy: 0.001)
        XCTAssertEqual(DemoMetrics.s3, MacOSControlMetrics.Spacing.s3, accuracy: 0.001)
        XCTAssertEqual(DemoMetrics.s4, MacOSControlMetrics.Spacing.s4, accuracy: 0.001)
        XCTAssertEqual(DemoMetrics.s5, MacOSControlMetrics.Spacing.s5, accuracy: 0.001)
        XCTAssertEqual(DemoMetrics.s6, MacOSControlMetrics.Spacing.s6, accuracy: 0.001)
        XCTAssertEqual(DemoMetrics.s8, MacOSControlMetrics.Spacing.s8, accuracy: 0.001)

        XCTAssertEqual(DemoMetrics.radiusXS, MacOSControlMetrics.Radius.xs, accuracy: 0.001)
        XCTAssertEqual(DemoMetrics.radiusSM, MacOSControlMetrics.Radius.sm, accuracy: 0.001)
        XCTAssertEqual(DemoMetrics.radiusMD, MacOSControlMetrics.Radius.md, accuracy: 0.001)
        XCTAssertEqual(DemoMetrics.radiusLG, MacOSControlMetrics.Radius.lg, accuracy: 0.001)
        XCTAssertEqual(DemoMetrics.radiusXL, MacOSControlMetrics.Radius.xl, accuracy: 0.001)
        XCTAssertEqual(
            DemoMetrics.radiusXL, MacOSControlMetrics.Radius.maximum, accuracy: 0.001,
            "nothing in the app is rounder than the largest radius the system allows")

        XCTAssertEqual(DemoMetrics.controlHeight, 28, accuracy: 0.001)
        XCTAssertEqual(
            DemoMetrics.navRowHeight, MacOSControlMetrics.List.sidebarRowHeight, accuracy: 0.001)
        XCTAssertEqual(
            DemoMetrics.settingsColumnWidth, MacOSControlMetrics.Form.contentMaxWidth, accuracy: 0.001)
    }

    /// Every corner the demo draws is on the radius scale, and nothing on any
    /// screen exceeds 12. The 16 / 20 / 22 / 24 / 26 / 30 the demo used to
    /// carry is what made it read as a consumer toy however correct its tones
    /// were.
    func testNoCornerOnAnyScreenExceedsTheRadiusScale() async {
        for screen in DemoScreen.allCases {
            let root = snapshotScreen(screen).runtime.root
            let offenders = allNodes(in: root) { node in
                // A capsule is `h / 2` by construction — a status dot, a
                // meter, a toggle track — and is allowed to exceed the scale
                // because it *is* the shape, not a rounded rectangle.
                let radius = node.cornerRadius
                guard radius > MacOSControlMetrics.Radius.maximum + 1 else { return false }
                let shortestSide = min(node.resolvedFrame.size.width, node.resolvedFrame.size.height)
                return radius < shortestSide * 0.5 - 0.5
            }
            XCTAssertTrue(
                offenders.isEmpty,
                "\(screen): \(offenders.count) surface(s) rounder than 12pt, e.g. "
                    + "\(offenders.first.map { "\($0.cornerRadius)pt on \($0.resolvedFrame.size)" } ?? "")")
        }
    }

    // MARK: - One signature

    /// The signature, and the whole of it: stop 1 is the accent fill, stop 2
    /// rotates per module, and every stop carries white at 5:1 so the hero's
    /// headline *and* its subtitle stay legible across the ramp.
    func testEveryHeroGradientStopCarriesWhite() async {
        var stops: [(String, Color)] = [("accent fill", DemoSignature.accentFill)]
        for module in DemoModule.allCases {
            stops.append((String(describing: module), module.signatureStop))
        }

        for stop in stops {
            XCTAssertEqual(stop.1.alpha, 1, accuracy: 0.001, "\(stop.0) is a wash, not a fill")
            let ratio = contrastRatio(text: Color.white, over: stop.1)
            XCTAssertGreaterThanOrEqual(
                ratio, 5.0,
                "\(stop.0) measures \(String(format: "%.2f", ratio)):1 against white")
        }

        // The subtitle rung is the tighter of the two, and it is measured
        // against **stop 1**: the gradient runs topLeading to bottomTrailing
        // and the subtitle sits in the card's upper-left third, where the ramp
        // has barely left the accent fill. The rotating stop only reaches the
        // opposite corner, where nothing is written.
        let subtitle = contrastRatio(
            text: DemoPalette(colorScheme: .dark).onAccentSecondary, over: DemoSignature.accentFill)
        XCTAssertGreaterThanOrEqual(
            subtitle, 4.5,
            "the hero subtitle measures \(String(format: "%.2f", subtitle)):1 on the accent fill")
    }

    /// **Exactly one saturated surface per screen.** Marks may take the accent
    /// — a chart bar, a meter fill, a selection indicator — but only one
    /// *surface* in the window is allowed to be a plate of colour, and on the
    /// dashboard it is the hero.
    func testOnlyOneSaturatedSurfacePerScreen() async {
        for screen in DemoScreen.allCases {
            let root = snapshotScreen(screen).runtime.root
            let saturated = allNodes(in: root) { node in
                guard let fill = node.backgroundColor, fill.alpha > 0.9 else { return false }
                guard chroma(of: fill) > 0.15 else { return false }
                return node.resolvedFrame.size.width >= 200
            }
            XCTAssertLessThanOrEqual(
                saturated.count, 1,
                "\(screen) carries \(saturated.count) saturated surfaces; the design allows one")
        }
    }

    /// The hero is the *same card* in both appearances. An opaque fill has no
    /// appearance behind it to vary with, and that single decision is most of
    /// what makes the light appearance a sibling rather than a paler cousin.
    func testHeroIsIdenticalInBothAppearances() async {
        var fills: [Color] = []
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let model = DemoDashboardModel()
            let root = laidOut(
                DemoRootView(model: model).environment(\.colorScheme, scheme),
                size: IntSize(width: 1280, height: 720))
            guard
                let headline = textNode(in: root, model.selectedModule.headline),
                let fill = nearestGradientStart(above: headline)
            else {
                return XCTFail("expected a hero headline on a filled card in \(scheme)")
            }
            fills.append(fill)
            XCTAssertGreaterThanOrEqual(
                contrastRatio(text: Color.white, over: fill), 5.0,
                "\(scheme): the hero headline clears 5:1")
        }

        XCTAssertEqual(fills.count, 2)
        XCTAssertEqual(fills[0], fills[1], "the hero resolves to one fill in both appearances")
        XCTAssertEqual(fills[0], DemoSignature.accentFill, "and that fill is the signature's first stop")
    }

    // MARK: - Dashboard composition

    /// The chart is built from views, so every part of it is a node: four
    /// gridlines behind the bars, a baseline visibly stronger than a gridline,
    /// a labelled y axis, a labelled x axis, and a value on the tallest bar.
    /// And **no plot background box** — the card is the plot's background.
    func testChartCarriesItsAxesAndNoPlotBox() async {
        let model = DemoDashboardModel()
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))
        let palette = DemoPalette(colorScheme: .dark)

        XCTAssertNotNil(textNode(in: root, "Render pipeline"), "the chart names itself")

        let bars = DemoChartCard.bars(interactions: model.interactionCount)
        for bar in bars {
            XCTAssertNotNil(
                textNode(in: root, bar.label), "the x axis labels bar \(bar.label)")
        }

        // Axis maximum: the quarter step is a nice number, so every tick is.
        XCTAssertNotNil(textNode(in: root, "0"), "the y axis is labelled at the baseline")
        XCTAssertNotNil(textNode(in: root, "10"), "and at its quarters")
        XCTAssertNotNil(textNode(in: root, "40"), "and at its maximum")

        let peak = bars.max { $0.value < $1.value }
        XCTAssertNotNil(
            textNode(in: root, "\(Int((peak?.value ?? 0).rounded()))"),
            "the tallest bar always carries its value")

        let gridlines = allNodes(in: root) { node in
            node.backgroundColor == palette.strokeSubtle
                && node.resolvedFrame.size.height <= 1.5
                && node.resolvedFrame.size.width > 200
        }
        XCTAssertGreaterThanOrEqual(gridlines.count, 4, "four gridlines behind the bars")

        let baselines = allNodes(in: root) { node in
            node.backgroundColor == palette.strokeStrong
                && node.resolvedFrame.size.height <= 1.5
                && node.resolvedFrame.size.width > 200
                && node.resolvedFrame.size.width < 1200
        }
        XCTAssertGreaterThanOrEqual(
            baselines.count, 1, "and a baseline drawn in the structural hairline, not the gridline one")
    }

    /// The value on the tallest bar sits in clear space *above* the axis
    /// maximum. With no strip reserved for it the label had nowhere to go but
    /// inside the plot, and the 100% gridline ran straight through the digits.
    func testTheTallestBarsValueClearsTheTopGridline() async {
        let model = DemoDashboardModel()
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))

        let bars = DemoChartCard.bars(interactions: model.interactionCount)
        guard let peak = bars.max(by: { $0.value < $1.value }),
            let value = textNode(in: root, "\(Int(peak.value.rounded()))"),
            let topGridline = chartGridlines(in: root).min(by: { absoluteY(of: $0) < absoluteY(of: $1) })
        else {
            return XCTFail("Expected a value on the tallest bar and gridlines behind the marks")
        }

        // The label's line box may kiss the 100% gridline by the point or two
        // of leading it carries above its own ink; what the strip guarantees
        // is that the *label* is above the line rather than across it. Before
        // the strip existed the label had nowhere to go but inside the plot
        // and the gridline ran through the middle of the digits.
        let valueCentre = absoluteY(of: value) + value.resolvedFrame.size.height / 2
        XCTAssertLessThan(
            valueCentre, absoluteY(of: topGridline) - 3,
            "the value on the tallest bar sits above the 100% gridline, not across it")
        XCTAssertGreaterThan(
            absoluteY(of: value), absoluteY(of: topGridline) - 24,
            "and inside the strip reserved for it rather than adrift above the card")
    }

    /// The chart's gridlines, told apart from every other subtle hairline on
    /// the screen by the one thing that is only true of them: they are
    /// exactly as wide as the baseline they stand on.
    private func chartGridlines(in root: ViewNode) -> [ViewNode] {
        let palette = DemoPalette(colorScheme: .dark)
        let baselines = allNodes(in: root) { node in
            node.backgroundColor == palette.strokeStrong
                && node.resolvedFrame.size.height <= 1.5
                && node.resolvedFrame.size.width > 200
                && node.resolvedFrame.size.width < 1200
        }
        guard let plotWidth = baselines.first?.resolvedFrame.size.width else { return [] }
        return allNodes(in: root) { node in
            node.backgroundColor == palette.strokeSubtle
                && node.resolvedFrame.size.height <= 1.5
                && abs(node.resolvedFrame.size.width - plotWidth) < 1
        }
    }

    /// The marks span the plot. A fixed 40pt ceiling with a fixed 8pt gap
    /// centres the group and leaves the rest of the plot empty — 100pt on
    /// each side at 1280 and 324 at 1720, which reads as a chart that failed
    /// to load the rest of its data.
    func testChartMarksSpanTheirPlotAtEveryWindowWidth() async {
        for width in [900, 1280, 1720] {
            let model = DemoDashboardModel()
            let root = laidOut(
                DemoRootView(model: model), size: IntSize(width: Int32(width), height: 720))

            let marks = allNodes(in: root) { node in
                node.cornerRadii != nil && node.resolvedFrame.size.height > 8
                    && node.resolvedFrame.size.width >= 12
            }
            guard let plot = chartGridlines(in: root).first,
                let leading = marks.min(by: { absoluteX(of: $0) < absoluteX(of: $1) }),
                let trailing = marks.max(by: {
                    absoluteX(of: $0) + $0.resolvedFrame.size.width
                        < absoluteX(of: $1) + $1.resolvedFrame.size.width
                })
            else {
                return XCTFail("Expected a plot and its marks at \(width)")
            }

            let plotLeading = absoluteX(of: plot)
            let plotTrailing = plotLeading + plot.resolvedFrame.size.width
            let markTrailing = absoluteX(of: trailing) + trailing.resolvedFrame.size.width
            // A few points of slack at each end: the leftover the gap could
            // not absorb is split between them, and it is never a margin.
            XCTAssertLessThan(
                absoluteX(of: leading) - plotLeading, 4,
                "at \(width) the series starts at the plot's leading edge")
            XCTAssertLessThan(
                plotTrailing - markTrailing, 4,
                "at \(width) the series ends at the plot's trailing edge")
        }
    }

    /// A screen title and the first column of the table under it start on the
    /// same vertical line. At 24 and 16 they were 8pt apart, which reads as a
    /// broken left edge no matter which of the two is the right answer.
    func testTheTableAlignsWithItsScreenTitle() async {
        let root = laidOut(
            DemoDataScreen(model: DemoDashboardModel()),
            size: IntSize(width: 1280, height: 720))

        guard let title = textNode(in: root, "Components"),
            let column = textNode(in: root, "Component"),
            let firstRow = textNode(in: root, "Render host")
        else {
            return XCTFail("Expected the header band, the column header and a row")
        }

        XCTAssertEqual(absoluteX(of: title), absoluteX(of: column), accuracy: 0.5)
        // The row's own leading content is the glyph, one gutter before the
        // name, so the name lands a glyph-plus-gap further in — but the
        // column it is under starts where the title does.
        XCTAssertGreaterThan(absoluteX(of: firstRow), absoluteX(of: column))
    }

    /// Every rule the app draws is *drawn*. A greedy hairline that measures
    /// its own intrinsic width is 0pt wide, laid out, and invisible — which
    /// is what the settings row rules and the table row rules were.
    func testEveryRowRuleIsActuallyDrawn() async {
        let palette = DemoPalette(colorScheme: .dark)

        let settings = laidOut(
            DemoSettingsScreen(model: DemoDashboardModel()),
            size: IntSize(width: 1280, height: 1300))
        let settingsRules = allNodes(in: settings) { node in
            node.backgroundColor == palette.strokeSubtle
                && node.resolvedFrame.size.height <= 1.5
                && node.resolvedFrame.size.width > 400
        }
        XCTAssertGreaterThanOrEqual(
            settingsRules.count, 8, "every settings row but the first is ruled off from the one above")

        let data = laidOut(
            DemoDataScreen(model: DemoDashboardModel()), size: IntSize(width: 1280, height: 720))
        let tableRules = allNodes(in: data) { node in
            node.backgroundColor == palette.strokeSubtle
                && node.resolvedFrame.size.height <= 1.5
                && node.resolvedFrame.size.width > 400
        }
        XCTAssertGreaterThanOrEqual(tableRules.count, 8, "and every table row carries its own rule")
    }

    /// The sidebar and the rail are the same kind of column, so their
    /// eyebrows start on the same inset from their own column edge.
    func testBothColumnsShareOneEyebrowRhythm() async {
        let root = laidOut(
            DemoDashboardScreen(model: DemoDashboardModel()),
            size: IntSize(width: 1280, height: 720))

        guard let workspace = textNode(in: root, "Workspace"),
            let detail = textNode(in: root, "Detail track"),
            let quick = textNode(in: root, "Quick actions")
        else {
            return XCTFail("Expected an eyebrow in each column")
        }

        let sidebarInset = absoluteX(of: workspace)
        let railInset = absoluteX(of: detail) - (1280 - DemoMetrics.railWidth)
        XCTAssertEqual(
            sidebarInset, railInset, accuracy: 1.0,
            "the rail's eyebrow is inset from its column exactly as the sidebar's is")
        XCTAssertEqual(absoluteX(of: detail), absoluteX(of: quick), accuracy: 0.5)
    }

    /// The stat card's hierarchy is carried by weight and rung, not by size:
    /// the eyebrow and the note sit on the third rung and the value on the
    /// first, one point of size apart from the body around them.
    func testStatCardSeparatesItsValueFromItsCaptions() async {
        let root = laidOut(
            VStack(alignment: .leading, spacing: 12) {
                Text("Third rung").foregroundStyle(.tertiary)
                Text("First rung").foregroundStyle(.primary)

                DemoStatCard(
                    card: DemoStat(
                        title: "Interactions",
                        systemImage: "bolt.fill",
                        value: "12",
                        delta: .up("12%"),
                        note: "vs last run"
                    )
                )
                .frame(width: 220)
            }
            .frame(width: 260),
            size: IntSize(width: 320, height: 400)
        )

        guard
            let third = textNode(in: root, "Third rung"),
            let first = textNode(in: root, "First rung"),
            let eyebrow = textNode(in: root, "Interactions"),
            let note = textNode(in: root, "vs last run"),
            let value = textNode(in: root, "12")
        else {
            return XCTFail("expected both reference rungs and the card's three lines")
        }

        XCTAssertEqual(
            eyebrow.textStyle.color, third.textStyle.color,
            "a stat card's eyebrow is a label, not a string you read on the way past")
        XCTAssertEqual(note.textStyle.color, third.textStyle.color, "and so is its note")
        XCTAssertEqual(
            value.textStyle.color, first.textStyle.color,
            "the metric itself is the one thing on the card you are meant to read")
        XCTAssertGreaterThan(
            value.textStyle.nativeFontSize ?? 0, eyebrow.textStyle.nativeFontSize ?? 0,
            "and it is the largest thing on the card")
    }

    /// Every number that changes at runtime is set in tabular figures, so a
    /// count ticking from 9 to 10 does not shove the label beside it.
    func testRuntimeNumbersAreTabular() async {
        let model = DemoDashboardModel()
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))

        guard let events = firstNode(in: root, matching: { $0.text == "0" }) else {
            return XCTFail("expected the toolbar's event count")
        }
        XCTAssertTrue(
            events.textStyle.monospacedDigits,
            "a live count is tabular or the row beside it moves every time it changes")
    }

    /// Sibling cards in the right rail are as wide as the rail's content
    /// column, not as wide as their own longest line — the rail used to read
    /// as a pile of differently sized boxes with a ragged right edge.
    func testDetailTrackCardsShareTheColumnWidth() async {
        let cards = DemoModule.layout.cards
        XCTAssertGreaterThanOrEqual(cards.count, 2)

        let columnWidth = 240.0
        let node = laidOut(
            VStack(alignment: .leading, spacing: 10) {
                DemoInfoCard(card: cards[0])
                DemoInfoCard(card: cards[1])
            }
            .frame(width: columnWidth),
            size: IntSize(width: 400, height: 500)
        )

        let widths = cards.prefix(2).compactMap { card -> Double? in
            guard
                let title = textNode(in: node, card.title),
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

    /// The rail is a column, not a panel: its cards span the rail inside its
    /// own 12pt gutter, and nothing wraps them in a second container.
    func testRightRailCardsSpanTheRailColumn() async {
        let layout = DemoLayout(size: CGSize(width: 1280, height: 655))
        let model = DemoDashboardModel()
        let root = laidOut(
            DemoRightRail(model: model, layout: layout)
                .frame(width: layout.railWidth, height: 520, alignment: .topLeading),
            size: IntSize(width: 420, height: 560)
        )

        var widest = 0.0
        for node in allNodes(in: root, matching: { $0.cornerRadius > 0 }) {
            widest = max(widest, node.resolvedFrame.size.width)
        }
        XCTAssertEqual(
            widest, layout.railInnerWidth, accuracy: 1,
            "a rail card is as wide as the rail's content column")
    }

    /// Whether the three stat cards stack is a question about the content
    /// column's *width* and nothing else. It used to ask `compact`, which is
    /// also true in a short window, so a wide short window stacked the band —
    /// tripling its height in the window with the least height to spend.
    func testStatBandStaysARowInAWideShortWindow() async {
        XCTAssertFalse(
            DemoLayout(size: CGSize(width: 1280, height: 720)).stacksMetrics,
            "a wide window keeps the band a row however short it is")
        XCTAssertTrue(
            DemoLayout(size: CGSize(width: 1000, height: 900)).stacksMetrics,
            "a narrow column stacks the band however tall the window is")
        XCTAssertFalse(
            DemoLayout(size: CGSize(width: 880, height: 900)).stacksMetrics,
            "and a window that gave up its rail has a column wide enough for the row")

        let model = DemoDashboardModel()
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))

        guard
            let interactions = textNode(in: root, "Interactions"),
            let module = textNode(in: root, "Module"),
            let frameCost = textNode(in: root, "Frame time")
        else {
            return XCTFail("expected the three stat eyebrows")
        }

        XCTAssertEqual(absoluteY(of: interactions), absoluteY(of: module), accuracy: 2)
        XCTAssertEqual(absoluteY(of: module), absoluteY(of: frameCost), accuracy: 2)
    }

    /// The centre pane scrolls, so its bottom edge cuts the column somewhere;
    /// what it must not do is cut a card in half. The stat band is the last
    /// thing the default window is expected to hold whole.
    func testDashboardFoldLeavesTheStatBandWhole() async {
        let size = IntSize(width: 1280, height: 720)
        let model = DemoDashboardModel()
        let root = laidOut(DemoRootView(model: model), size: size)

        guard
            let moduleCaption = textNode(in: root, "Module"),
            let moduleCard = enclosingSurface(of: moduleCaption)
        else {
            return XCTFail("expected a Module stat card")
        }

        let fold = Double(size.height)
        let cardTop = absoluteY(of: moduleCard)
        let cardBottom = cardTop + moduleCard.resolvedFrame.size.height

        XCTAssertFalse(
            cardTop < fold && cardBottom > fold,
            "the fold at \(fold) runs through the Module card (\(cardTop)...\(cardBottom))")
        XCTAssertLessThanOrEqual(
            cardBottom, fold,
            "and the band is fully above it, not pushed off the bottom entirely")
    }

    /// The hero's action row is one row at every window size the shell can be
    /// dragged to, and its buttons keep the system's control height. The pills
    /// used to be squeezed to 0.9pt at 640 by a fixed-height card that could
    /// not hold what the narrow branch put in it.
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
                let open = textNode(in: root, "Open Layout"),
                let cycle = textNode(in: root, "Cycle mode"),
                let openButton = enclosingSurface(of: open)
            else {
                return XCTFail("expected both hero buttons at \(size.width)x\(size.height)")
            }

            XCTAssertEqual(
                absoluteY(of: open), absoluteY(of: cycle), accuracy: 2,
                "one row at \(size.width)x\(size.height)")
            XCTAssertGreaterThanOrEqual(
                openButton.resolvedFrame.size.height, DemoMetrics.controlHeight,
                "at \(size.width)x\(size.height) a button is as tall as it asked to be, "
                    + "not squeezed by an overflowing card")
        }
    }

    /// The rail carries two cards and two flat rows in the height the centre
    /// pane spends on one card. Its last row has to be whole and above the
    /// fold, or the column reads as cut off.
    func testRightRailFitsAboveTheFold() async {
        let size = IntSize(width: 1280, height: 720)
        let model = DemoDashboardModel()
        let root = laidOut(DemoRootView(model: model), size: size)

        guard let resize = textNode(in: root, "Resize Panes") else {
            return XCTFail("expected the last quick-action row")
        }

        let rowBottom = absoluteY(of: resize) + resize.resolvedFrame.size.height
        XCTAssertLessThanOrEqual(
            rowBottom, Double(size.height),
            "the rail's last row is whole and above the fold")
    }

    // MARK: - Settings

    /// A settings pane is a **leading-anchored column**. The title sits on the
    /// section boxes' own edge, and that edge is the page margin — not the
    /// middle of a 1280pt window with ~340pt of dead space on each side.
    func testSettingsColumnIsLeadingAnchored() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))

        guard
            let title = firstNode(
                in: root,
                matching: { $0.text == "Settings" && ($0.textStyle.nativeFontSize ?? 0) > 20 }),
            let sectionHeader = textNode(in: root, "Profile")
        else {
            return XCTFail("expected a pane title and a section header")
        }

        XCTAssertEqual(
            absoluteX(of: title), absoluteX(of: sectionHeader), accuracy: 8,
            "the title leads on the same edge as the section headers under it")
        XCTAssertLessThanOrEqual(
            absoluteX(of: title), DemoMetrics.s6 + 4,
            "and that edge is the page margin, not the centre of the window")
    }

    /// A section header is a **heading**, not an eyebrow: 15/600 on the
    /// primary rung, attached to the group under it. The 11pt dim uppercase
    /// string it used to be belongs to neither of the boxes it floats between.
    func testSettingsSectionHeadersAreHeadingsNotEyebrows() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 720))

        guard
            let header = firstNode(in: root, matching: { $0.text == "Preferences" }),
            let body = firstNode(in: root, matching: { $0.text == "Sound Effects" })
        else {
            return XCTFail("expected a section header and a row title")
        }

        XCTAssertEqual(
            header.textStyle.nativeFontSize ?? 0,
            MacOSControlMetrics.Typography.formSectionHeaderSize,
            accuracy: 0.5,
            "a settings section header is the `section` role")
        XCTAssertGreaterThan(
            header.textStyle.nativeFontSize ?? 0, body.textStyle.nativeFontSize ?? 0,
            "and it reads as a heading over the rows it names")
    }

    /// Every settings row reads left to right: label, then control. The
    /// trailing-aligned label gutter is a System Settings idiom and the most
    /// obviously borrowed thing the pane used to do.
    func testSettingsRowsReadLabelThenControl() async {
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
            absoluteY(of: label), absoluteY(of: value), accuracy: 8,
            "label and value share the row")
        XCTAssertGreaterThan(
            absoluteX(of: value), absoluteX(of: label),
            "and the control is trailing, the label leading")

        // The label column starts at the box's own inset — every row on the
        // same edge — rather than being right-aligned into a shared gutter.
        let rowLabels = ["Display Name", "Theme", "Items Per Page"].compactMap { title in
            firstNode(in: root, matching: { node in node.text == title })
        }
        XCTAssertEqual(rowLabels.count, 3)
        for label in rowLabels.dropFirst() {
            XCTAssertEqual(
                absoluteX(of: label), absoluteX(of: rowLabels[0]), accuracy: 1,
                "every row's label leads on the same edge")
        }
    }

    /// Exactly one filled accent button on the pane, and the destructive
    /// action is not it: a filled red button in a settings list is a threat,
    /// not an option.
    func testSettingsHasOneFilledAccentButton() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        let root = laidOut(DemoRootView(model: model), size: IntSize(width: 1280, height: 900))

        guard
            let save = textNode(in: root, "Save Settings"),
            let reset = textNode(in: root, "Reset To Defaults")
        else {
            return XCTFail("expected the actions row")
        }

        XCTAssertEqual(
            nearestFill(above: save), DemoSignature.accentFill,
            "Save Settings is the pane's one accent moment")

        let resetFill = nearestFill(above: reset)
        XCTAssertNotNil(resetFill)
        XCTAssertLessThan(
            chroma(of: resetFill ?? .clear), 0.1,
            "Reset To Defaults is a neutral chassis; only its label is in danger")
        XCTAssertEqual(
            reset.textStyle.color, DemoPalette(colorScheme: .dark).danger,
            "and the label is the one that carries the warning")
    }

    /// No section header is left orphaned on the fold line — a heading fully
    /// visible with nothing of its group under it captions the bottom edge of
    /// the window rather than the rows it names.
    func testNoSettingsHeaderIsOrphanedOnTheFold() async {
        let size = IntSize(width: 1280, height: 720)
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        let root = laidOut(DemoRootView(model: model), size: size)

        let fold = Double(size.height)
        let groups = [
            ("Profile", "Display Name"),
            ("Preferences", "Enable Animations"),
            ("Resources", "Storage Used"),
            ("Actions", "Save Settings"),
        ]

        for group in groups {
            guard let header = firstNode(in: root, matching: { $0.text == group.0 }) else {
                return XCTFail("expected the \(group.0) header")
            }
            let headerBottom = absoluteY(of: header) + header.resolvedFrame.size.height
            guard headerBottom < fold else { continue }

            guard let firstRow = firstNode(in: root, matching: { $0.text == group.1 }) else {
                return XCTFail("expected \(group.1) under \(group.0)")
            }
            XCTAssertLessThan(
                absoluteY(of: firstRow), fold,
                "\(group.0) is visible but its first row is not — an orphaned heading on the fold")
        }
    }

    // MARK: - Data

    /// One row, one line, one height for the table. The rows used to carry a
    /// stacked version-over-status block, which made every row a two-line box.
    func testComponentRowIsOneLineTall() async {
        let first = DemoComponent.defaults[0]
        let second = DemoComponent.defaults[1]
        let metrics = DemoTableMetrics(width: 480)
        let node = laidOut(
            VStack(alignment: .leading, spacing: 0) {
                DemoComponentRow(component: first, metrics: metrics, isSelected: false) {}
                DemoComponentRow(component: second, metrics: metrics, isSelected: false) {}
            },
            size: IntSize(width: 480, height: 400)
        )

        guard
            let firstName = textNode(in: node, first.name),
            let secondName = textNode(in: node, second.name)
        else {
            return XCTFail("expected both component names to be laid out")
        }

        let pitch = absoluteY(of: secondName) - absoluteY(of: firstName)
        XCTAssertEqual(
            pitch, DemoMetrics.listRowHeight + 1, accuracy: 1.5,
            "the pitch is one row plus its rule")
    }

    /// The table is a table: a header row of four labelled columns whose
    /// trailing columns line up with the data under them.
    func testTableHeaderColumnsLineUpWithTheirData() async {
        let size = IntSize(width: 1280, height: 720)
        let model = DemoDashboardModel()
        model.selectedScreen = .data
        let root = laidOut(DemoRootView(model: model), size: size)

        for column in ["Component", "Version", "Load", "Status"] {
            XCTAssertNotNil(textNode(in: root, column), "the table names its \(column) column")
        }

        guard
            let versionHeader = textNode(in: root, "Version"),
            let versionCell = textNode(in: root, DemoComponent.defaults[0].version)
        else {
            return XCTFail("expected a version header and a version cell")
        }

        let headerRight = absoluteX(of: versionHeader) + versionHeader.resolvedFrame.size.width
        let cellRight = absoluteX(of: versionCell) + versionCell.resolvedFrame.size.width
        XCTAssertEqual(
            headerRight, cellRight, accuracy: 3,
            "a trailing column header ends on the same edge as the values under it")
    }

    /// The Load column is what makes the table read as a product rather than a
    /// list: a meter, then the number. And the meter's own colour reports the
    /// state — accent ink until the load is the story.
    func testLoadColumnDrawsAMeter() async {
        let palette = DemoPalette(colorScheme: .dark)
        XCTAssertEqual(DemoMeter.fillColor(for: 0.34, palette: palette), palette.accentInk)
        XCTAssertEqual(DemoMeter.fillColor(for: 0.80, palette: palette), palette.warning)
        XCTAssertEqual(DemoMeter.fillColor(for: 0.95, palette: palette), palette.danger)

        let component = DemoComponent.defaults[0]
        let root = laidOut(
            DemoComponentRow(
                component: component, metrics: DemoTableMetrics(width: 900), isSelected: false
            ) {},
            size: IntSize(width: 900, height: 80)
        )

        XCTAssertNotNil(textNode(in: root, component.loadPercent), "the load is also written out")

        let track = allNodes(in: root) { node in
            node.backgroundColor == palette.surface3
                && node.resolvedFrame.size.height <= DemoMetrics.meterThickness + 0.5
        }
        XCTAssertFalse(track.isEmpty, "the load cell draws a meter track")
    }

    /// The exception gets the chip; the normal case stays quiet. `Healthy` is
    /// a dot beside a secondary word with no fill behind it at all.
    func testOnlyTheDegradedStatusCarriesAChip() async {
        let degraded = DemoComponent.defaults.first { !$0.isHealthy }
        let healthy = DemoComponent.defaults.first { $0.isHealthy }
        guard let degraded, let healthy else {
            return XCTFail("the fixture data carries both states")
        }
        let palette = DemoPalette(colorScheme: .dark)

        let degradedRoot = laidOut(
            DemoStatusCell(component: degraded).environment(\.colorScheme, .dark),
            size: IntSize(width: 200, height: 40))
        let healthyRoot = laidOut(
            DemoStatusCell(component: healthy).environment(\.colorScheme, .dark),
            size: IntSize(width: 200, height: 40))

        guard
            let degradedWord = textNode(in: degradedRoot, degraded.statusLabel),
            let healthyWord = textNode(in: healthyRoot, healthy.statusLabel)
        else {
            return XCTFail("expected both status words")
        }

        XCTAssertEqual(
            degradedWord.textStyle.color, palette.warning,
            "the exception says so in its own hue")
        XCTAssertEqual(
            nearestFill(above: degradedWord), palette.statusWash(palette.warning),
            "on a wash, not a saturated fill")

        XCTAssertNotEqual(
            healthyWord.textStyle.color, palette.success,
            "the nominal case is a dot beside plain text")
        XCTAssertNil(
            nearestFill(above: healthyWord),
            "and it carries no chip at all")

        let dots = allNodes(in: healthyRoot) { node in
            node.backgroundColor == palette.success
                && node.resolvedFrame.size.width <= DemoMetrics.dotSize + 0.5
        }
        XCTAssertEqual(dots.count, 1, "the healthy row's colour rides a dot")
    }

    /// The selected row is a wash with a thin leading bar, not a full-bleed
    /// saturated band with white text on it — the loudest object in the app
    /// for the least important reason.
    func testSelectedRowIsAWashWithALeadingBar() async {
        let component = DemoComponent.defaults[0]
        let palette = DemoPalette(colorScheme: .dark)
        let root = laidOut(
            DemoComponentRow(
                component: component, metrics: DemoTableMetrics(width: 900), isSelected: true
            ) {}
            .environment(\.colorScheme, .dark),
            size: IntSize(width: 900, height: 80)
        )

        guard let name = textNode(in: root, component.name) else {
            return XCTFail("expected the row's name")
        }
        XCTAssertEqual(
            nearestFill(above: name), palette.accentWashStrong,
            "a selected row is a wash on the page's own ladder")

        let indicators = allNodes(in: root) { node in
            node.backgroundColor == palette.accentInk
                && node.resolvedFrame.size.width <= 2.5
                && node.resolvedFrame.size.height >= DemoMetrics.listRowHeight - 1
        }
        XCTAssertEqual(indicators.count, 1, "and a 2px accent bar at its leading edge says which one")
    }

    /// The footer inspector is a *bar*: its own material, closed at the top by
    /// a structural hairline, and never brighter than the table it closes in
    /// dark or darker than it in light.
    func testDataInspectorSitsOnABarRatherThanAboveOrBelowThePage() async {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let model = DemoDashboardModel()
            model.selectedScreen = .data
            let root = laidOut(
                DemoRootView(model: model).environment(\.colorScheme, scheme),
                size: IntSize(width: 1280, height: 720))

            guard let load = textNode(in: root, "Current load") else {
                return XCTFail("expected the inspector's load eyebrow in \(scheme)")
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

            let demo = DemoPalette(colorScheme: scheme)
            let composited = Color(
                red: fill.red * fill.alpha + demo.base.red * (1 - fill.alpha),
                green: fill.green * fill.alpha + demo.base.green * (1 - fill.alpha),
                blue: fill.blue * fill.alpha + demo.base.blue * (1 - fill.alpha),
                alpha: 1
            )
            let barLuminance = relativeLuminance(of: composited)
            let bodyLuminance = relativeLuminance(of: demo.surface0)

            if scheme == .dark {
                XCTAssertLessThanOrEqual(
                    barLuminance, bodyLuminance + 0.002,
                    "a dark bar is never brighter than the table it closes")
            } else {
                XCTAssertGreaterThanOrEqual(
                    barLuminance, bodyLuminance - 0.02,
                    "a light bar is never darker than the table it closes")
            }
        }
    }

    /// The inspector is pinned to the bottom of the window at every size: a
    /// greedy table takes exactly what its siblings leave.
    func testDataScreenInspectorLandsOnTheBottomInset() async {
        let size = IntSize(width: 1280, height: 720)
        let model = DemoDashboardModel()
        model.selectedScreen = .data
        let root = laidOut(DemoRootView(model: model), size: size)

        var lowest = 0.0
        for node in allNodes(in: root, matching: { ($0.text ?? "").isEmpty == false }) {
            lowest = max(lowest, absoluteY(of: node) + node.resolvedFrame.size.height)
        }

        XCTAssertGreaterThan(
            lowest, Double(size.height) - DemoMetrics.footerHeight,
            "the inspector is pinned under a greedy table, so it ends on the bottom inset")
        XCTAssertLessThanOrEqual(lowest, Double(size.height), "and it stays inside the window")
    }
}
