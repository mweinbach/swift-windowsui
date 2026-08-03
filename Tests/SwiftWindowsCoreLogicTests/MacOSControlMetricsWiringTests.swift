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

            for row in node.children {
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
