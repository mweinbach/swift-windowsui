import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

@MainActor
private func buildNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600),
    configure: (ViewBuildContext) -> ViewBuildContext = { $0 }
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = configure(ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {}))
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

/// Builds a view *and lays it out*, so assertions can read the frames the
/// layout pass produced rather than the declared chrome.
@MainActor
private func layoutNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600)
) -> (runtime: RetainedViewRuntime, node: ViewNode) {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
    let node = view.makeComponent(context: context).makeNode(runtime: runtime)
    node.frame = Rect(origin: .zero, size: size)
    runtime.root.addChild(node)
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    _ = runtime.renderFrame()
    return (runtime, node)
}

/// A laid-out node's horizontal span in `ancestor`'s coordinate space.
@MainActor
private func horizontalSpan(of node: ViewNode, in ancestor: ViewNode) -> (minX: Double, maxX: Double) {
    var originX: Double = 0
    var current: ViewNode? = node
    while let walk = current, walk !== ancestor {
        originX += walk.resolvedFrame.origin.x
        current = walk.parent
    }
    return (originX, originX + node.resolvedFrame.size.width)
}

@MainActor
private func flatten(_ node: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = [node]
    for child in node.children {
        result.append(contentsOf: flatten(child))
    }
    return result
}

/// List row chrome and shipped control metrics.
///
/// `RetainedListChrome` had no separator field at all, so a row rule was
/// not representable anywhere in the stack and the default list style
/// rendered as bare strings. The `ControlSize` extensions had drifted to
/// 1.4x–3.5x their macOS reference with only three of the divergences
/// recorded in docs/MacOSDesignParity.md.
final class ListChromeAndMetricsTests: XCTestCase {

    // MARK: - Finding 9: separators are representable, and on by default

    func testDefaultListStyleDeclaresRowSeparators() async {
        for style in [ListStyle.automatic, .plain] {
            let chrome = style.retainedChrome(palette: .darkStandard)
            XCTAssertTrue(chrome.drawsRowSeparators, "\(style) rules between rows like macOS")
            XCTAssertEqual(chrome.rowMinHeight, MacOSControlMetrics.List.plainRowHeight)
        }
    }

    /// An NSTableView shorter than its scroll view still paints its body down
    /// to the clip view's bottom edge. With no background at all, a short list
    /// in a tall slot stopped at its last row and everything below it was bare
    /// window — the list read as rows floating over a hole.
    func testDefaultListStyleCarriesABodyThatFillsItsSlot() async {
        for scheme in [ColorScheme.light, .dark] {
            let palette = ControlPalette.resolve(colorScheme: scheme)
            for style in [ListStyle.automatic, .plain] {
                XCTAssertEqual(
                    style.retainedChrome(palette: palette).backgroundColor,
                    palette.controlBackground,
                    "\(style) draws the text background, in whichever appearance it is in"
                )
            }
        }

        await MainActor.run {
            let slotHeight: Double = 400
            let node = buildNode(
                List {
                    Text("Inbox")
                    Text("Sent")
                }
                .frame(width: 300, height: slotHeight),
                size: Size(width: 600, height: 600)
            )
            let runtime = RetainedViewRuntime(root: ViewNode())
            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: 600, height: 600))
            _ = runtime.renderFrame()

            guard
                let body = flatten(node).first(where: {
                    $0.backgroundColor == ControlPalette.darkStandard.controlBackground
                })
            else {
                return XCTFail("the list body is a painted surface")
            }
            XCTAssertEqual(
                body.resolvedFrame.height, slotHeight, accuracy: 0.51,
                "The body fills the slot, not the two rows in it"
            )
            let rowsHeight = body.children.reduce(0.0) { $0 + $1.resolvedFrame.height }
            XCTAssertLessThan(rowsHeight, slotHeight, "…while the rows stay content-sized")
        }
    }

    // MARK: - `.inset` is a body style

    /// `.inset` had no body: no fill, no ring, no corners, no rule, and a 6pt
    /// gap holding the rows apart. Four strings floated on the window
    /// background — which is the one thing an *inset table* is not, because
    /// the inset in the name is the row content's inset from a body's edge.
    func testInsetListStyleDrawsARoundedTextBackgroundBody() async {
        for scheme in [ColorScheme.light, .dark] {
            let palette = ControlPalette.resolve(colorScheme: scheme)
            let chrome = ListStyle.inset.retainedChrome(palette: palette)
            XCTAssertEqual(
                chrome.backgroundColor, palette.controlBackground,
                "\(scheme): an inset table's rows stand on the text background"
            )
            XCTAssertEqual(chrome.cornerRadius, MacOSControlMetrics.List.insetCornerRadius)
            XCTAssertEqual(chrome.borderColor, palette.separator)
            XCTAssertEqual(chrome.borderWidth, 1)
            XCTAssertEqual(
                chrome.padding.leading, MacOSControlMetrics.List.contentInset,
                "\(scheme): and are inset into it"
            )
            XCTAssertEqual(chrome.padding.trailing, MacOSControlMetrics.List.contentInset)
            XCTAssertEqual(chrome.padding.top, MacOSControlMetrics.List.insetVerticalInset)
            XCTAssertEqual(chrome.rowMinHeight, MacOSControlMetrics.List.plainRowHeight)
            XCTAssertEqual(chrome.defaultSpacing, 0, "\(scheme): rows in a table are adjacent, not spaced")
        }
    }

    /// Stripes and rules are alternatives. AppKit's alternating row colours
    /// *are* the row boundary; a table that drew both reads as a spreadsheet.
    func testInsetListRulesBetweenRowsUnlessItIsStriping() async {
        let plainInset = ListStyle.inset.retainedChrome(palette: .darkStandard)
        XCTAssertTrue(plainInset.drawsRowSeparators)
        XCTAssertFalse(plainInset.alternatesRowBackgrounds)

        let striped = ListStyle.inset(alternatesRowBackgrounds: true).retainedChrome(palette: .darkStandard)
        XCTAssertTrue(striped.alternatesRowBackgrounds)
        XCTAssertFalse(striped.drawsRowSeparators, "the stripe is the boundary")
    }

    func testListEmitsAHairlineBetweenAdjacentRows() async {
        await MainActor.run {
            let node = buildNode(
                List {
                    Text("Inbox")
                    Text("Sent")
                    Text("Archive")
                })
            let separatorColor = ControlPalette.darkStandard.separator
            let rules = flatten(node).filter { $0.backgroundColor == separatorColor && $0.text == nil }
            XCTAssertEqual(rules.count, 2, "Three rows are separated by two rules — never one after the last")
            for rule in rules {
                XCTAssertEqual(rule.layoutFillAxes, .horizontalOnly, "A rule fills the row width")
                XCTAssertGreaterThan(rule.preferredSize?.height ?? 0, 0)
                XCTAssertEqual(rule.preferredSize?.width ?? -1, 0, "A rule has no extent of its own across")
            }
        }
    }

    func testSingleRowListDrawsNoSeparator() async {
        await MainActor.run {
            let node = buildNode(List { Text("Only") })
            let separatorColor = ControlPalette.darkStandard.separator
            let rules = flatten(node).filter { $0.backgroundColor == separatorColor && $0.text == nil }
            XCTAssertTrue(rules.isEmpty)
        }
    }

    // MARK: - Finding 8/9: a rule takes its colour from the appearance

    func testSeparatorColorFollowsAppearance() async {
        await MainActor.run {
            let dark = buildNode(Divider()) { $0.withEnvironmentValue(\.colorScheme, .dark) }
            let light = buildNode(Divider()) { $0.withEnvironmentValue(\.colorScheme, .light) }
            XCTAssertEqual(dark.backgroundColor, ControlPalette.darkStandard.separator)
            XCTAssertEqual(light.backgroundColor, ControlPalette.lightStandard.separator)
            XCTAssertNotEqual(dark.backgroundColor, light.backgroundColor)
        }
    }

    /// `NSColor.separatorColor` is 10% — the 0.22 white this used to draw
    /// is roughly twice the macOS rule.
    func testSeparatorAlphaMatchesAppKit() async {
        XCTAssertEqual(ControlPalette.darkStandard.separator.alpha, 0.10, accuracy: 0.001)
        XCTAssertEqual(ControlPalette.lightStandard.separator.alpha, 0.10, accuracy: 0.001)
    }

    // MARK: - Finding 10: a selected row is a solid fill, not an outlined chip

    func testSelectedRowIsSolidAccentWithNoBorder() async {
        await MainActor.run {
            let node = buildNode(
                List(selection: .constant(Set(["a"]))) {
                    Text("Alpha").tag("a")
                    Text("Beta").tag("b")
                })
            let filled = flatten(node).filter { ($0.backgroundColor?.alpha ?? 0) > 0.9 && $0.text == nil }
            let selected = filled.first { node in
                let fill = node.backgroundColor ?? .clear
                return fill.blue > 0.9 && fill.red < 0.2
            }
            XCTAssertNotNil(selected, "The selected row fills solid with the accent colour")
            XCTAssertEqual(selected?.borderWidth ?? -1, 0, "macOS draws no border around a selected row")
            XCTAssertEqual(
                selected?.cornerRadius ?? -1, MacOSControlMetrics.Button.regularCornerRadius,
                "A 28pt row takes a small radius, not the 10pt floating-chip radius")
        }
    }

    /// An AppKit inset table insets the row *box*: the selection fill and the
    /// rule between rows start and end on the same two vertical lines, because
    /// they are two decorations of one inset row rectangle. A rule that ran the
    /// body's full width under a selection inset from it would read as two
    /// different tables stacked on each other.
    ///
    /// This is a geometry assertion, not a chrome one: the inset is expressed
    /// as the list's own padding, so the only way to see the two agree is to
    /// lay the list out and compare the frames the pass produced.
    func testInsetListRulesOnTheSameVerticalsAsItsSelectionFill() async {
        await MainActor.run {
            for style in [ListStyle.inset, .automatic] {
                let width: Double = 320
                let (_, node) = layoutNode(
                    List(selection: .constant(Set(["a"]))) {
                        Text("Alpha").tag("a")
                        Text("Beta").tag("b")
                        Text("Gamma").tag("c")
                    }
                    .listStyle(style),
                    size: Size(width: width, height: 240)
                )

                // Spans are measured against the list, not against whatever
                // container a rule happens to be wrapped in: an inset applied
                // by wrapping the rule in a padded panel is exactly the
                // divergence this test exists to catch, and reading the rule's
                // own parent-relative frame would hide it.
                let rules = flatten(node).filter(\.isSeparatorRule).map { horizontalSpan(of: $0, in: node) }
                let rows = node.children.filter { !$0.isSeparatorRule && $0.onActivate != nil }
                    .map { horizontalSpan(of: $0, in: node) }
                XCTAssertFalse(rules.isEmpty, "\(style): adjacent unselected rows are ruled")
                XCTAssertEqual(rows.count, 3, "\(style): three selectable rows")

                let inset = MacOSControlMetrics.List.contentInset
                for row in rows {
                    XCTAssertEqual(row.minX, inset, accuracy: 0.01, "\(style): row inset")
                    XCTAssertEqual(row.maxX, width - inset, accuracy: 0.01, "\(style): row inset")
                }
                for rule in rules {
                    XCTAssertEqual(
                        rule.minX, rows[0].minX, accuracy: 0.01,
                        "\(style): a rule starts where the selection fill starts")
                    XCTAssertEqual(
                        rule.maxX, rows[0].maxX, accuracy: 0.01,
                        "\(style): a rule ends where the selection fill ends")
                }
            }
        }
    }

    func testUnemphasizedSelectionUsesTheNeutralFill() async {
        await MainActor.run {
            let node = buildNode(
                List(selection: .constant(Set(["a"]))) {
                    Text("Alpha").tag("a")
                    Text("Beta").tag("b")
                }
            ) { $0.withEnvironmentValue(\.controlActiveState, .inactive) }
            let neutral = ControlPalette.darkStandard.unemphasizedSelectedBackground
            XCTAssertTrue(
                flatten(node).contains { $0.backgroundColor == neutral },
                "A list without key focus dims its selection to the neutral grey, as AppKit does")
        }
    }

    // MARK: - Finding 3: shipped metrics are the reference plus one delta

    func testShippedControlHeightsAreReferencePlusTheNamedDelta() async {
        let delta = ControlSize.windowsPointerPadding
        XCTAssertEqual(delta, 6, "One named Windows pointer delta, not per-control guesswork")
        XCTAssertEqual(
            ControlSize.regular.singleLineTextInputSize.height,
            MacOSControlMetrics.TextField.regularHeight + delta)
        XCTAssertEqual(
            ControlSize.regular.pickerMenuPreferredSize.height,
            MacOSControlMetrics.PopUpButton.regularHeight + delta)
        XCTAssertEqual(
            ControlSize.large.singleLineTextInputSize.height,
            (MacOSControlMetrics.TextField.largeHeight + delta * 1.25).rounded())
    }

    /// A progress bar is not a pointer target, so it takes the macOS
    /// thickness exactly.
    func testProgressBarTakesTheMacOSThickness() async {
        XCTAssertEqual(
            ControlSize.regular.progressPreferredSize.height,
            MacOSControlMetrics.ProgressBar.regularHeight)
    }

    func testStepperHalfDerivesFromTheNSStepperButton() async {
        let half = ControlSize.regular.stepperButtonPreferredSize
        XCTAssertEqual(half.width, MacOSControlMetrics.Stepper.buttonSize.width + ControlSize.windowsPointerPadding)
        XCTAssertLessThan(half.height, MacOSControlMetrics.Stepper.regularSize.height)
        XCTAssertLessThan(half.width, 30, "A stepper half stays narrow — the pair used to measure 68pt across")
    }

    // MARK: - Finding 11: the stepper is a vertical chevron pair

    func testStepperStacksItsHalvesVerticallyWithChevrons() async {
        await MainActor.run {
            let node = buildNode(Stepper("Items Per Page", value: .constant(10), in: 0...20))
            let texts = flatten(node).compactMap(\.text)
            XCTAssertFalse(texts.contains("+"), "NSStepper draws chevrons, not ASCII glyphs: \(texts)")
            XCTAssertFalse(texts.contains("-"), "NSStepper draws chevrons, not ASCII glyphs: \(texts)")
            XCTAssertTrue(
                texts.contains(SymbolIcon.chevronUp.rawValue) && texts.contains(SymbolIcon.chevronDown.rawValue),
                "An up chevron above a down chevron")

            let buttons = flatten(node).filter {
                $0.accessibilityLabel == "Increment" || $0.accessibilityLabel == "Decrement"
            }
            XCTAssertEqual(buttons.count, 2)
            // One bezel holding [increment][seam rule][decrement]: the ring is
            // the bezel's, and the hairline between the halves is a node.
            let bezel = flatten(node).first { candidate in
                candidate.children.count == 3
                    && candidate.children.allSatisfy {
                        $0.accessibilityLabel == "Increment"
                            || $0.accessibilityLabel == "Decrement"
                            || $0.isSeparatorRule
                    }
            }
            XCTAssertNotNil(bezel, "The two halves share one bezel")
            XCTAssertEqual(bezel?.children.first?.accessibilityLabel, "Increment", "Increment sits on top")
            XCTAssertEqual(bezel?.children[1].isSeparatorRule, true, "A hairline divides the halves")
            XCTAssertEqual(bezel?.borderWidth, 1, "The bezel carries the ring, not each half")
        }
    }

    // MARK: - Finding 3: the slider groove is the macOS groove

    func testSliderTrackMatchesTheMacOSThickness() async {
        await MainActor.run {
            let node = buildNode(Slider(value: .constant(0.5), in: 0...1))
            let grooves = flatten(node).filter { $0.frame.size.height > 0 && $0.frame.size.height <= 6 }
            XCTAssertTrue(
                grooves.contains { $0.frame.size.height == MacOSControlMetrics.Slider.trackThickness },
                "The linear track is 4pt, like NSSlider")
        }
    }
}
