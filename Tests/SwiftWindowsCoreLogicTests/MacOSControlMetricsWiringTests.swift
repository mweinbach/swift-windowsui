import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

/// `MacOSControlMetrics` used to be inert: the constants were pinned in
/// docs/MacOSDesignParity.md and referenced by nothing, so the parity tests
/// compared constants against themselves while button padding, list rows,
/// the toolbar band and the segmented track each drifted on their own.
/// These tests assert the constants now drive real layout output.
@MainActor
private func buildNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600)
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func layoutNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600)
) -> (runtime: RetainedViewRuntime, node: ViewNode) {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
    let node = view.makeComponent(context: context).makeNode(runtime: runtime)
    runtime.root.addChild(node)
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    _ = runtime.renderFrame()
    return (runtime, node)
}

@MainActor
private func firstNavigationTextNode(in node: ViewNode, matching text: String) -> ViewNode? {
    if node.text == text {
        return node
    }
    for child in node.children {
        if let found = firstNavigationTextNode(in: child, matching: text) {
            return found
        }
    }
    return nil
}

final class MacOSControlMetricsWiringTests: XCTestCase {

    // MARK: - Button (NSButton push bezel)

    func testButtonPillIsABezelAroundItsLabelNotTheLabelsAdvanceBox() async {
        await MainActor.run {
            let (_, node) = layoutNode(Button("OK") {}, size: Size(width: 400, height: 200))
            let label = node.children[0]

            XCTAssertGreaterThanOrEqual(
                node.resolvedFrame.size.height,
                MacOSControlMetrics.Button.regularHeight
            )
            let bezel = retainedButtonContentMetrics(style: .automatic, controlSize: .regular)
            XCTAssertEqual(
                node.resolvedFrame.size.width - label.resolvedFrame.size.width,
                bezel.padding.leading + bezel.padding.trailing,
                accuracy: 0.001
            )
        }
    }

    func testButtonControlSizesTrackTheMacOSHeights() async {
        await MainActor.run {
            let sizes: [(ControlSize, Double)] = [
                (.mini, MacOSControlMetrics.Button.miniHeight),
                (.small, MacOSControlMetrics.Button.smallHeight),
                (.regular, MacOSControlMetrics.Button.regularHeight),
                (.large, MacOSControlMetrics.Button.largeHeight),
            ]
            for (controlSize, expected) in sizes {
                XCTAssertEqual(
                    retainedButtonContentMetrics(style: .automatic, controlSize: controlSize).minimumHeight,
                    expected
                )
            }
        }
    }

    func testBezelLessButtonStylesOptOutOfTheContentInset() async {
        await MainActor.run {
            for style in [ButtonStyle.plain, .borderless, .link] {
                let metrics = retainedButtonContentMetrics(style: style, controlSize: .regular)
                XCTAssertEqual(metrics.padding, .zero)
                XCTAssertEqual(metrics.minimumHeight, 0)
            }
        }
    }

    // MARK: - Divider (separator hairline)

    func testDividerFillsItsContainerAndStaysAHairline() async {
        await MainActor.run {
            let (_, node) = layoutNode(
                VStack(spacing: 0) {
                    Text("ABOVE")
                    Divider()
                    Text("BELOW")
                }
                .frame(width: 300),
                size: Size(width: 400, height: 200)
            )

            let stack = node.children[0]
            let divider = stack.children[1]
            XCTAssertEqual(divider.resolvedFrame.size.width, 300, accuracy: 0.001)
            XCTAssertEqual(divider.resolvedFrame.size.height, 1, accuracy: 0.001)
        }
    }

    func testDividerIsOnePhysicalPixelAtHighDisplayScale() async {
        await MainActor.run {
            let node = buildNode(
                VStack {
                    Divider()
                }
                .environment(\.displayScale, 2)
                .environment(\.pixelLength, 0.5)
            )

            XCTAssertEqual(node.children[0].preferredSize?.height, 0.5)
        }
    }

    // MARK: - List rows (NSTableView)

    func testPlainListRowsUseTheMacOSRowBoxAndContentInset() async {
        await MainActor.run {
            let (_, node) = layoutNode(
                List {
                    Text("ONE")
                    Text("TWO")
                },
                size: Size(width: 400, height: 300)
            )

            guard case .stack(let layout) = node.layoutMode else {
                return XCTFail("Expected the list to be a retained scroll stack")
            }
            XCTAssertEqual(layout.padding.leading, MacOSControlMetrics.List.contentInset)
            XCTAssertEqual(layout.padding.trailing, MacOSControlMetrics.List.contentInset)

            // Rows only: the default style interleaves a hairline rule
            // between adjacent rows, which is deliberately not a row box.
            let separator = ControlPalette.darkStandard.separator
            for row in node.children where row.backgroundColor != separator {
                XCTAssertGreaterThanOrEqual(
                    row.resolvedFrame.size.height,
                    MacOSControlMetrics.List.plainRowHeight
                )
                XCTAssertEqual(
                    row.resolvedFrame.size.width,
                    400 - 2 * MacOSControlMetrics.List.contentInset,
                    accuracy: 0.001
                )
            }
        }
    }

    func testSidebarListRowsUseTheSidebarRowHeight() async {
        await MainActor.run {
            let (_, node) = layoutNode(
                List {
                    Text("ONE")
                }
                .listStyle(.sidebar),
                size: Size(width: 400, height: 300)
            )

            XCTAssertGreaterThanOrEqual(
                node.children[0].resolvedFrame.size.height,
                MacOSControlMetrics.List.sidebarRowHeight
            )
        }
    }

    // MARK: - Navigation toolbar band (NSToolbar)

    func testNavigationTitleBandUsesTheToolbarHeightAndAHairline() async {
        await MainActor.run {
            let (_, node) = layoutNode(
                NavigationStack {
                    Text("BODY")
                        .navigationTitle("TITLE")
                },
                size: Size(width: 800, height: 400)
            )

            let band = node.children[0]
            let header = band.children[0]
            let separator = band.children[1]

            XCTAssertEqual(
                header.resolvedFrame.size.height,
                MacOSControlMetrics.Toolbar.regularHeight,
                accuracy: 0.001
            )
            // Full bleed, no rounded card, one hairline along the bottom.
            XCTAssertEqual(header.resolvedFrame.size.width, 800, accuracy: 0.001)
            XCTAssertEqual(header.cornerRadius, 0)
            XCTAssertEqual(header.borderWidth, 0)
            XCTAssertEqual(separator.resolvedFrame.size.height, 1, accuracy: 0.001)
            XCTAssertEqual(separator.resolvedFrame.size.width, 800, accuracy: 0.001)
        }
    }

    /// The band this stack draws is the *content pane's* header — macOS puts
    /// the window title in chrome the stack does not own — so it is set at
    /// pane scale, not at `NSWindow.title` scale. At 13pt the title read as a
    /// stray label adrift in an otherwise empty 52pt band.
    func testNavigationTitleIsSetAtContentPaneScale() async {
        await MainActor.run {
            let (_, node) = layoutNode(
                NavigationStack {
                    Text("BODY")
                        .navigationTitle("TITLE")
                },
                size: Size(width: 800, height: 400)
            )

            let titleNode = firstNavigationTextNode(in: node.children[0], matching: "TITLE")
            XCTAssertEqual(
                titleNode?.textStyle.nativeFontSize,
                MacOSControlMetrics.Typography.largeTitleSize,
                "a pane title is largeTitle (26), not the 13pt window title"
            )
            XCTAssertLessThan(
                MacOSControlMetrics.Typography.largeTitleSize,
                MacOSControlMetrics.Toolbar.regularHeight,
                "and it still has to fit the band it is set in"
            )
        }
    }

    func testACompactNavigationTitleIsSetAtToolbarTitleScale() async {
        await MainActor.run {
            let (_, node) = layoutNode(
                NavigationStack {
                    Text("BODY")
                        .navigationTitle("TITLE")
                        .navigationBarTitleDisplayMode(.inline)
                },
                size: Size(width: 800, height: 400)
            )

            let titleNode = firstNavigationTextNode(in: node.children[0], matching: "TITLE")
            XCTAssertEqual(
                titleNode?.textStyle.nativeFontSize,
                MacOSControlMetrics.Typography.title2Size,
                "`.inline` is macOS's unified-compact toolbar title — title2 semibold (17)"
            )
        }
    }

    // MARK: - Segmented control (NSSegmentedControl)

    func testSegmentedPickerTrackUsesTheMacOSControlHeight() async {
        await MainActor.run {
            let node = buildNode(
                Picker("Theme", selection: .constant(1)) {
                    Text("Light").tag(0)
                    Text("Dark").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            )

            XCTAssertEqual(
                node.intrinsicContentSize().height,
                MacOSControlMetrics.PopUpButton.regularHeight,
                accuracy: 0.001
            )
        }
    }

    func testSegmentedPickerTrackFillsTheControlColumn() async {
        await MainActor.run {
            let (_, node) = layoutNode(
                Form {
                    Picker("Theme", selection: .constant(1)) {
                        Text("Light").tag(0)
                        Text("Dark").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                },
                size: Size(width: 400, height: 200)
            )

            // The Form fills the window and the track fills the Form's
            // content column, minus the form's own padding.
            XCTAssertEqual(node.resolvedFrame.size.width, 400, accuracy: 0.001)
            XCTAssertGreaterThan(node.children[0].resolvedFrame.size.width, 300)
        }
    }

    // MARK: - Tab bar (a selector bar, not a segmented control)

    /// A tab bar and a segmented picker are not the same control, and drawing
    /// them with the same one put a rounded grey capsule holding three chained
    /// buttons across the top of every screen. The band is the **chrome tone**,
    /// square and full bleed, closed by one hairline; a tab is transparent at
    /// rest with no border and no shadow; and the selection is a short accent
    /// bar under the label. The segmented control keeps its groove — a
    /// segmented control *is* a groove.
    ///
    /// `chromeBand`, not `base`. Painted in the window's own backdrop tone the
    /// bar had nothing to be a bar against: on the dashboard it and the
    /// toolbar band under it sampled byte-identical to the columns beside
    /// them, so the top 88pt was one flat field. It sits a full ramp rung up
    /// now, on the same tone the `.bar` material solves for, which is what
    /// makes the two stacked bands read as one chrome unit.
    func testTabBarIsASelectorBarNotAGroove() async {
        await MainActor.run {
            let bar = MacOSControlMetrics.SelectorBar.self
            for scheme in [ColorScheme.dark, ColorScheme.light] {
                let palette = ControlPalette.resolve(colorScheme: scheme)
                let band = Self.tabBandNode(colorScheme: scheme)
                let row = band.children[0]

                XCTAssertEqual(
                    band.backgroundColor, palette.chromeBand, "\(scheme) band is the chrome tone")
                XCTAssertNotEqual(
                    band.backgroundColor, palette.base,
                    "\(scheme) a band painted in the backdrop tone is not a band")
                XCTAssertEqual(row.cornerRadius, 0, "\(scheme) band is square")
                XCTAssertNil(row.backgroundColor, "\(scheme) no recessed track")
                XCTAssertEqual(row.borderWidth, 0, "\(scheme) no ring around the band")
                XCTAssertEqual(row.preferredSize?.height, bar.bandHeight, "\(scheme) band height")

                XCTAssertEqual(band.children.count, 2)
                XCTAssertEqual(
                    band.children[1].backgroundColor, palette.separator,
                    "\(scheme) band is closed by the subtle hairline")

                XCTAssertEqual(row.children.count, 2)
                for (index, tab) in row.children.enumerated() {
                    XCTAssertEqual(tab.backgroundColor ?? .clear, .clear, "\(scheme) tab \(index) fill")
                    XCTAssertEqual(tab.borderWidth, 0, "\(scheme) tab \(index) border")
                    XCTAssertEqual(tab.cornerRadius, bar.itemCornerRadius, "\(scheme) tab \(index) radius")
                }
            }
        }
    }

    /// The selection indicator is in the tree for *every* tab, transparent on
    /// the ones that are not selected: a bar that appears and disappears
    /// would move the label by its own height on every switch.
    func testSelectedTabCarriesAnAccentBarAndTheOthersReserveItsSpace() async {
        await MainActor.run {
            let bar = MacOSControlMetrics.SelectorBar.self
            for scheme in [ColorScheme.dark, ColorScheme.light] {
                let palette = ControlPalette.resolve(colorScheme: scheme)
                let row = Self.tabBandNode(colorScheme: scheme).children[0]

                let indicators = row.children.map { $0.children[1] }
                XCTAssertEqual(indicators.count, 2)
                for indicator in indicators {
                    XCTAssertEqual(indicator.preferredSize, bar.indicatorSize, "\(scheme) indicator box")
                    XCTAssertEqual(indicator.cornerRadius, bar.indicatorCornerRadius, "\(scheme) indicator radius")
                }
                XCTAssertEqual(
                    indicators[0].backgroundColor, palette.accentForeground,
                    "\(scheme) the selected tab's bar is the accent as ink")
                XCTAssertEqual(
                    indicators[1].backgroundColor, .clear,
                    "\(scheme) an unselected tab reserves the bar's space and paints nothing")
            }
        }
    }

    /// The selected label moves one *rung* and one *weight* step. Size is
    /// what a tab bar cannot spend: a label that grows on selection re-lays
    /// the whole bar out under the pointer that just clicked it.
    func testSelectedTabLabelIsPromotedRatherThanInverted() async {
        await MainActor.run {
            for scheme in [ColorScheme.dark, ColorScheme.light] {
                let palette = ControlPalette.resolve(colorScheme: scheme)
                let row = Self.tabBandNode(colorScheme: scheme).children[0]
                guard let selected = Self.firstText(in: row.children[0]),
                    let unselected = Self.firstText(in: row.children[1])
                else {
                    return XCTFail("Expected a label on each tab")
                }
                XCTAssertEqual(selected.textStyle.color, palette.label, "\(scheme) selected rung")
                XCTAssertEqual(unselected.textStyle.color, palette.secondaryLabel, "\(scheme) resting rung")
                XCTAssertGreaterThan(
                    selected.textStyle.weight.gdiWeight, unselected.textStyle.weight.gdiWeight,
                    "\(scheme) selected label carries the heavier weight")
                XCTAssertEqual(
                    selected.textStyle.nativeFontSize, unselected.textStyle.nativeFontSize,
                    "\(scheme) selection never changes the type size")
            }
        }
    }

    @MainActor
    private static func tabBandNode(colorScheme: ColorScheme) -> ViewNode {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 800, height: 600) },
            invalidateHandler: {},
            environmentValuesProvider: { EnvironmentValues(colorScheme: colorScheme) }
        )
        let node =
            TabView {
                Text("First page")
                    .tabItem { Text("First") }
                Text("Second page")
                    .tabItem { Text("Second") }
            }
            .makeComponent(context: context)
            .makeNode(runtime: runtime)
        // container > the band (an item row plus the hairline that closes it).
        return node.children[0]
    }

    @MainActor
    private static func firstText(in node: ViewNode) -> ViewNode? {
        if node.text != nil {
            return node
        }
        for child in node.children {
            if let found = firstText(in: child) {
                return found
            }
        }
        return nil
    }

    // MARK: - Stack spacing

    func testStacksDefaultToTheMacOSStackSpacing() async {
        await MainActor.run {
            let node = buildNode(
                VStack {
                    Text("ONE")
                    Text("TWO")
                }
            )

            guard case .stack(let layout) = node.layoutMode else {
                return XCTFail("Expected a retained stack")
            }
            XCTAssertEqual(layout.spacing, MacOSControlMetrics.Layout.defaultStackSpacing)
        }
    }

    func testExplicitZeroSpacingStillMeansZero() async {
        await MainActor.run {
            let node = buildNode(
                VStack(spacing: 0) {
                    Text("ONE")
                    Text("TWO")
                }
            )

            guard case .stack(let layout) = node.layoutMode else {
                return XCTFail("Expected a retained stack")
            }
            XCTAssertEqual(layout.spacing, 0)
        }
    }

    // MARK: - Text alignment

    func testTextDefaultsToLeadingAlignment() async {
        await MainActor.run {
            let node = buildNode(Text("HELLO"))
            XCTAssertEqual(node.textStyle.alignment, .leading)
        }
    }

    func testButtonLabelsStayCenteredInTheirChrome() async {
        await MainActor.run {
            let node = buildNode(Button("OK") {})
            XCTAssertEqual(node.children[0].textStyle.alignment, .center)
        }
    }
}
