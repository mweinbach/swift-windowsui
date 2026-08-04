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
            let bezel = flatten(node).first { candidate in
                candidate.children.count == 2
                    && candidate.children.allSatisfy {
                        $0.accessibilityLabel == "Increment" || $0.accessibilityLabel == "Decrement"
                    }
            }
            XCTAssertNotNil(bezel, "The two halves share one bezel")
            XCTAssertEqual(bezel?.children.first?.accessibilityLabel, "Increment", "Increment sits on top")
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
