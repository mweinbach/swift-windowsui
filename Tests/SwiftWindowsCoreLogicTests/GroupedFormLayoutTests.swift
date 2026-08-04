import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

/// A macOS grouped form is a two-column grid inside a centred content
/// column, not a stack of independent controls stretched edge to edge.
///
/// Each test here corresponds to one structural claim: rows share a label
/// column, the column is centred at the macOS content width, section
/// headers sit outside the box they name, a segmented control is
/// intrinsically sized, and a light-mode group box is near-flat.
@MainActor
final class GroupedFormLayoutTests: XCTestCase {

    // MARK: - Helpers

    private func buildNode<V: View>(
        _ view: V,
        size: Size = Size(width: 1200, height: 800),
        colorScheme: ColorScheme = .dark
    ) -> ViewNode {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
            .withEnvironmentValue(\.colorScheme, colorScheme)
        return view.makeComponent(context: context).makeNode(runtime: runtime)
    }

    private func layoutNode<V: View>(
        _ view: V,
        size: Size = Size(width: 1200, height: 800),
        colorScheme: ColorScheme = .dark
    ) -> ViewNode {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
            .withEnvironmentValue(\.colorScheme, colorScheme)
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        node.frame = Rect(origin: .zero, size: size)
        runtime.root.addChild(node)
        runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
        _ = runtime.renderFrame()
        return node
    }

    /// The styled column inside a Form's centring box.
    private func contentColumn(of form: ViewNode) -> ViewNode {
        form.children[0]
    }

    /// The rounded box of a grouped section — the second child of the
    /// header-plus-box wrapper.
    private func groupBox(of section: ViewNode) -> ViewNode {
        section.children.count == 2 ? section.children[1] : section
    }

    /// The box's *rows*, with the hairlines a grouped section rules between
    /// them dropped. A rule is chrome, not a row.
    private func formRows(of section: ViewNode) -> [ViewNode] {
        groupBox(of: section).children.filter { !$0.isSeparatorRule }
    }

    /// Every non-empty run of text in a subtree, in traversal order.
    private func texts(in node: ViewNode) -> [String] {
        descendants(of: node).compactMap { $0.text }.filter { !$0.isEmpty }
    }

    private func descendants(of node: ViewNode) -> [ViewNode] {
        var found: [ViewNode] = [node]
        var index = 0
        while index < found.count {
            found.append(contentsOf: found[index].children)
            index += 1
        }
        return found
    }

    // MARK: - Item 1: rows share one label column

    func testGroupedFormRowsShareOneTrailingAlignedLabelColumn() async {
        let node = layoutNode(
            Form {
                Section("PREFERENCES") {
                    Toggle("On", isOn: .constant(true))
                    Toggle("A Considerably Longer Row Label", isOn: .constant(false))
                }
            }
        )
        let section = contentColumn(of: node).children[0]
        let rows = formRows(of: section)
        XCTAssertEqual(rows.count, 2)

        var labelColumns: [ViewNode] = []
        for row in rows {
            guard let index = row.formRowLabelChildIndex, row.children.indices.contains(index) else {
                return XCTFail("Every labelled control in a Form builds a two-column row")
            }
            labelColumns.append(row.children[index])
        }

        XCTAssertEqual(
            labelColumns[0].resolvedFrame.width,
            labelColumns[1].resolvedFrame.width,
            accuracy: 0.51,
            "Rows in one section share a single label column, not a per-row one"
        )
        XCTAssertGreaterThan(
            labelColumns[0].resolvedFrame.width,
            labelColumns[0].children[0].resolvedFrame.width,
            "The short label's column is widened to the group's widest label"
        )
        for labelColumn in labelColumns {
            let label = labelColumn.children[0]
            XCTAssertEqual(
                label.resolvedFrame.maxX,
                labelColumn.resolvedFrame.width,
                accuracy: 0.51,
                "Labels are trailing-aligned inside the shared column"
            )
        }
        // …and the control leads the value column beside it.
        let valueColumn = rows[0].children[1]
        XCTAssertEqual(valueColumn.children[0].resolvedFrame.minX, 0, accuracy: 0.51)
        XCTAssertGreaterThan(
            valueColumn.resolvedFrame.width,
            valueColumn.children[0].resolvedFrame.width,
            "A switch leads the value column at its intrinsic width"
        )
    }

    /// macOS aligns a settings pane on one leading column: the label edges
    /// in "General" line up with the label edges in "Appearance". The boxes
    /// group rows, they do not each own a grid.
    func testLabelColumnIsSharedAcrossEveryFormSection() async {
        let node = layoutNode(
            Form {
                Section("SHORT") {
                    Toggle("A", isOn: .constant(true))
                }
                Section("LONG") {
                    Toggle("An Entirely Longer Label Than The Other Section", isOn: .constant(true))
                }
            }
        )
        let sections = contentColumn(of: node).children
        XCTAssertEqual(sections.count, 2)
        let columns = sections.map { section -> ViewNode in
            let row = formRows(of: section)[0]
            return row.children[row.formRowLabelChildIndex ?? 0]
        }
        XCTAssertEqual(
            columns[0].resolvedFrame.width,
            columns[1].resolvedFrame.width,
            accuracy: 0.51,
            "One label column spans the whole Form, not one per group box"
        )
        XCTAssertEqual(
            columns[0].resolvedFrame.maxX,
            columns[1].resolvedFrame.maxX,
            accuracy: 0.51,
            "…so the two sections' labels end on the same edge"
        )
        XCTAssertGreaterThan(
            columns[0].resolvedFrame.width,
            columns[0].children[0].resolvedFrame.width,
            "The short section's column is widened to the form's widest label"
        )
    }

    /// The indent that lines a bare button up with the controls above it is
    /// resolved against the *form* column too — a section that resolved a
    /// narrower one first must not leave a stale inset behind.
    func testLabellessRowsFollowTheFormWideColumn() async {
        let node = layoutNode(
            Form {
                Section("SHORT") {
                    Toggle("A", isOn: .constant(true))
                    Button("Sync Now") {}
                }
                Section("LONG") {
                    Toggle("An Entirely Longer Label Than The Other Section", isOn: .constant(true))
                }
            }
        )
        let sections = contentColumn(of: node).children
        // The *other* section is the one that sets the column, and the
        // button in this one has to follow it — a per-section inset left
        // behind by the first pass is exactly the bug this catches.
        let widestRow = formRows(of: sections[1])[0]
        guard let labelIndex = widestRow.formRowLabelChildIndex else {
            return XCTFail("A labelled Toggle builds a form row")
        }
        let indentedRow = formRows(of: sections[0])[1]
        XCTAssertEqual(
            indentedRow.children[0].resolvedFrame.minX,
            widestRow.children[labelIndex].resolvedFrame.width + MacOSControlMetrics.Form.labelColumnGap,
            accuracy: 0.51,
            "The button leads the value column the whole form settled on"
        )
    }

    func testLabellessRowsAreIndentedToTheValueColumn() async {
        let node = layoutNode(
            Form {
                Section("RESOURCES") {
                    ProgressView("Sync Progress", value: 0.4)
                    Button("Sync Now") {}
                }
            }
        )
        let rows = formRows(of: contentColumn(of: node).children[0])
        XCTAssertEqual(rows.count, 2)
        let labelledRow = rows[0]
        guard let labelIndex = labelledRow.formRowLabelChildIndex else {
            return XCTFail("A labelled ProgressView builds a form row")
        }
        let labelColumnWidth = labelledRow.children[labelIndex].resolvedFrame.width
        let valueColumnOrigin = labelColumnWidth + MacOSControlMetrics.Form.labelColumnGap
        XCTAssertNil(rows[1].formRowLabelChildIndex)
        XCTAssertEqual(
            rows[1].children[0].resolvedFrame.minX,
            valueColumnOrigin,
            accuracy: 0.51,
            "A bare button lines up with the controls above it instead of hugging the box edge"
        )
    }

    // MARK: - Item 6: a grouped box rules between every row

    /// macOS System Settings separates *every* row inside a grouped box. A
    /// box that ruled only where the app happened to write a `Divider` read
    /// as an arbitrary rhythm — one line above "Font Scale" and none between
    /// the three toggles above it.
    func testGroupedFormSectionRulesBetweenEveryPairOfRows() async {
        let node = layoutNode(
            Form {
                Section("PREFERENCES") {
                    Toggle("One", isOn: .constant(true))
                    Toggle("Two", isOn: .constant(false))
                    Toggle("Three", isOn: .constant(true))
                }
            }
        )
        let box = groupBox(of: contentColumn(of: node).children[0])
        let rules = box.children.filter(\.isSeparatorRule)
        XCTAssertEqual(rules.count, 2, "Three rows are separated by two rules — never after the last")
        XCTAssertEqual(box.children.count, 5, "…interleaved, not appended")
        XCTAssertFalse(box.children[0].isSeparatorRule, "A box never opens on a rule")
        XCTAssertFalse(box.children[4].isSeparatorRule, "…nor closes on one")
        let palette = ControlPalette.resolve(colorScheme: .dark)
        for rule in rules {
            XCTAssertEqual(rule.backgroundColor, palette.separator)
            XCTAssertGreaterThan(rule.resolvedFrame.width, 0, "A rule spans the box's content width")
            XCTAssertLessThanOrEqual(rule.resolvedFrame.height, 1.01, "One physical pixel")
        }
        // Row-to-row distance is unchanged: the rule sits in the middle of
        // the same gap rather than adding a second one — and it costs the
        // gap nothing, so a pane is the same height at every backing scale.
        XCTAssertEqual(
            box.children[2].resolvedFrame.minY - box.children[0].resolvedFrame.maxY,
            MacOSControlMetrics.Form.rowSpacing,
            accuracy: 0.01
        )
    }

    /// A hairline is one *device* pixel, so a grouped pane whose rows are all
    /// ruled would drift shorter at 2x if the rule added to the gap. In a
    /// scrolling settings pane that moves the fold — a different app at every
    /// DPI, and exactly what `ScenePrimitiveScaleInvarianceTests` catches.
    func testGroupedFormRowRhythmIsIdenticalAtEveryBackingScale() async {
        func boxHeight(displayScale: Double) -> Double {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let size = Size(width: 1200, height: 800)
            let context = ViewBuildContext(
                canvasSizeProvider: { size },
                invalidateHandler: {},
                environmentValuesProvider: {
                    EnvironmentValues(displayScale: displayScale, pixelLength: 1 / displayScale)
                }
            )
            let view = Form {
                Section("PREFERENCES") {
                    Toggle("One", isOn: .constant(true))
                    Toggle("Two", isOn: .constant(false))
                    Toggle("Three", isOn: .constant(true))
                    Toggle("Four", isOn: .constant(false))
                }
            }
            let node = view.makeComponent(context: context).makeNode(runtime: runtime)
            node.frame = Rect(origin: .zero, size: size)
            runtime.root.addChild(node)
            runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
            _ = runtime.renderFrame()
            return groupBox(of: contentColumn(of: node).children[0]).resolvedFrame.height
        }

        XCTAssertEqual(boxHeight(displayScale: 1), boxHeight(displayScale: 2), accuracy: 0.01)
        XCTAssertEqual(boxHeight(displayScale: 1), boxHeight(displayScale: 3), accuracy: 0.01)
    }

    /// An app that writes its own rule keeps exactly one line, not three.
    func testAppAuthoredDividerIsNotDoubledByTheSectionRules() async {
        let node = layoutNode(
            Form {
                Section("PREFERENCES") {
                    Toggle("One", isOn: .constant(true))
                    Divider()
                    Toggle("Two", isOn: .constant(false))
                }
            }
        )
        let box = groupBox(of: contentColumn(of: node).children[0])
        XCTAssertEqual(box.children.count, 3, "row, the app's own rule, row")
        XCTAssertTrue(box.children[1].isSeparatorRule)
        XCTAssertFalse(box.children[0].isSeparatorRule)
        XCTAssertFalse(box.children[2].isSeparatorRule)
    }

    /// A single-row box has nothing to separate, and a `Section` outside a
    /// `Form` keeps the list-group layout it has always had.
    func testSectionRulesAreGroupedFormScoped() async {
        let single = layoutNode(
            Form {
                Section("PROFILE") {
                    Toggle("Only", isOn: .constant(true))
                }
            }
        )
        XCTAssertTrue(
            groupBox(of: contentColumn(of: single).children[0]).children.allSatisfy { !$0.isSeparatorRule },
            "One row, no rule"
        )

        let standalone = buildNode(
            Section("PREFERENCES") {
                Toggle("One", isOn: .constant(true))
                Toggle("Two", isOn: .constant(false))
            }
        )
        XCTAssertTrue(
            descendants(of: standalone).allSatisfy { !$0.isSeparatorRule },
            "The automatic rules are Form-scoped, like the label column"
        )
    }

    func testListRowsInsideAFormAreNotGroupedFormRows() async {
        let node = buildNode(
            Form {
                List {
                    Toggle("Enable", isOn: .constant(true))
                }
            }
        )
        let list = contentColumn(of: node).children[0]
        XCTAssertTrue(
            descendants(of: list).allSatisfy { $0.formRowLabelChildIndex == nil },
            "A List's rows are table rows; they do not inherit the form's label column"
        )
    }

    /// A password row is a labelled row like any other. `TextField` moved its
    /// title into the shared label column when the grouped form arrived;
    /// `SecureField` did not, so a settings pane rendered "User [admin]" over
    /// a nameless password well — the one row in the pane with nothing in the
    /// label column. This is what the light gallery tier's `form-settings`
    /// entry shows, in both appearances.
    func testSecureFieldInAFormPutsItsTitleInTheLabelColumn() async {
        let node = layoutNode(
            Form {
                Section("ACCOUNT") {
                    TextField("User", text: .constant("admin"))
                    SecureField("Password", text: .constant("hunter2"))
                }
            }
        )
        let rows = formRows(of: contentColumn(of: node).children[0])
        XCTAssertEqual(rows.count, 2)

        var labelColumns: [ViewNode] = []
        for row in rows {
            guard let index = row.formRowLabelChildIndex, row.children.indices.contains(index) else {
                return XCTFail("A SecureField in a Form builds the same two-column row a TextField does")
            }
            labelColumns.append(row.children[index])
        }
        XCTAssertTrue(
            texts(in: labelColumns[1]).contains("Password"),
            "The SecureField's title is the row's label, not its placeholder"
        )
        XCTAssertEqual(
            labelColumns[0].resolvedFrame.width,
            labelColumns[1].resolvedFrame.width,
            accuracy: 0.51,
            "The password row joins the form's shared label column"
        )
        // The title moved out of the well, so nothing is left echoing it
        // inside the field itself.
        XCTAssertFalse(
            texts(in: rows[1].children[1]).contains("Password"),
            "A form row's field shows a prompt or nothing — never the label again"
        )
    }

    func testSectionsOutsideAFormKeepTheirPlainRowLayout() async {
        let node = buildNode(
            Section("PREFERENCES") {
                Toggle("Enable", isOn: .constant(true))
            }
        )
        XCTAssertTrue(
            descendants(of: node).allSatisfy { $0.formRowLabelChildIndex == nil },
            "The grouped-form grid is Form-scoped; a standalone Section is untouched"
        )
    }

    // MARK: - Item 2: centred content column

    func testFormCentresItsContentColumnAtTheMacOSContentWidth() async {
        let width: Double = 1200
        let node = layoutNode(
            Form {
                Section("PROFILE") {
                    Toggle("Enable", isOn: .constant(true))
                }
            },
            size: Size(width: width, height: 800)
        )
        XCTAssertEqual(node.resolvedFrame.width, width, accuracy: 0.51)
        let column = contentColumn(of: node)
        XCTAssertEqual(
            column.resolvedFrame.width,
            MacOSControlMetrics.Form.contentMaxWidth,
            accuracy: 0.51,
            "A Form is a content column, not an edge-to-edge box"
        )
        XCTAssertEqual(
            column.resolvedFrame.minX,
            (width - MacOSControlMetrics.Form.contentMaxWidth) * 0.5,
            accuracy: 1,
            "The content column is centred in the window"
        )
    }

    func testNarrowWindowsGiveTheFormTheirFullWidth() async {
        let width: Double = 420
        let node = layoutNode(
            Form {
                Section("PROFILE") {
                    Toggle("Enable", isOn: .constant(true))
                }
            },
            size: Size(width: width, height: 600)
        )
        XCTAssertEqual(
            contentColumn(of: node).resolvedFrame.width,
            width,
            accuracy: 0.51,
            "The max width is a ceiling, never a floor"
        )
    }

    // MARK: - Item 3: intrinsically sized segmented control

    func testSegmentedPickerDoesNotStretchToFillItsContainer() async {
        let node = layoutNode(
            VStack {
                Picker("Theme", selection: .constant(0)) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            },
            size: Size(width: 900, height: 200)
        )
        guard
            let track = descendants(of: node).first(where: {
                $0.cornerRadius == MacOSControlMetrics.Button.regularCornerRadius && $0.clipsToBounds
                    && $0.children.count == 3
            })
        else {
            return XCTFail("segmented track not found")
        }
        XCTAssertGreaterThan(track.resolvedFrame.width, 0)
        XCTAssertLessThan(
            track.resolvedFrame.width, 400,
            "An NSSegmentedControl is intrinsically sized; it stretches only when asked"
        )
        let segmentWidths = track.children.map(\.resolvedFrame.width)
        XCTAssertEqual(segmentWidths[0], segmentWidths[1], accuracy: 0.51)
        XCTAssertEqual(segmentWidths[1], segmentWidths[2], accuracy: 0.51)
    }

    func testSegmentedPickerInAFormLeadsItsValueColumn() async {
        let node = layoutNode(
            Form {
                Section("PROFILE") {
                    Picker("Theme", selection: .constant(0)) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
            }
        )
        let row = formRows(of: contentColumn(of: node).children[0])[0]
        XCTAssertNotNil(row.formRowLabelChildIndex)
        let valueColumn = row.children[1]
        let track = valueColumn.children[0]
        XCTAssertEqual(track.resolvedFrame.minX, 0, accuracy: 0.51)
        XCTAssertLessThan(
            track.resolvedFrame.width,
            valueColumn.resolvedFrame.width,
            "The track leads the value column at its intrinsic width instead of filling it"
        )
    }

    // MARK: - Item 4: headers outside the box

    func testGroupedFormSectionHeaderSitsOutsideAndAboveTheBox() async {
        let node = buildNode(
            Form {
                Section("PROFILE") {
                    Toggle("Enable", isOn: .constant(true))
                }
            }
        )
        let section = contentColumn(of: node).children[0]
        XCTAssertEqual(section.children.count, 2, "A grouped section is a header plus a box")
        XCTAssertEqual(section.borderWidth, 0, "The header wrapper carries no chrome of its own")
        XCTAssertEqual(section.sectionHeaderChildCount, 1)

        let header = section.children[0]
        let box = section.children[1]
        XCTAssertTrue(
            descendants(of: header).contains { $0.text == "PROFILE" },
            "The header text lives above the box"
        )
        XCTAssertFalse(
            descendants(of: box).contains { $0.text == "PROFILE" },
            "…and no longer inside it"
        )
        XCTAssertEqual(box.borderWidth, 1)
        XCTAssertEqual(box.cornerRadius, MacOSControlMetrics.GroupBox.cornerRadius)
        XCTAssertEqual(box.sectionHeaderChildCount, 0, "The box hosts rows only")
    }

    func testSectionHeaderStaysInsideTheBoxOutsideAForm() async {
        let node = buildNode(
            Section("PROFILE") {
                Text("ROW")
            }
        )
        XCTAssertEqual(
            node.sectionHeaderChildCount, 1,
            "A List-style section keeps its header as the box's first child"
        )
        XCTAssertTrue(node.children.contains { $0.text == "PROFILE" })
    }

    // MARK: - Item 5: near-flat light-mode group box

    func testLightModeGroupedContainerShadowIsNearlyInvisible() async {
        XCTAssertLessThan(
            ControlPalette.lightStandard.groupedContainerShadow.alpha, 0.06,
            "A macOS light-mode group box is a hairline ring, not a shadowed card"
        )
        XCTAssertGreaterThan(
            ControlPalette.darkStandard.groupedContainerShadow.alpha,
            ControlPalette.lightStandard.groupedContainerShadow.alpha,
            "Dark mode carries the depth the low-contrast hairline cannot"
        )
    }

    func testGroupedFormBoxTakesItsShadowFromTheAppearance() async {
        for scheme in [ColorScheme.light, .dark] {
            let node = buildNode(
                Form {
                    Section("PROFILE") {
                        Toggle("Enable", isOn: .constant(true))
                    }
                },
                colorScheme: scheme
            )
            let box = groupBox(of: contentColumn(of: node).children[0])
            let palette = ControlPalette.resolve(colorScheme: scheme)
            XCTAssertEqual(box.shadowColor, palette.groupedContainerShadow)
            XCTAssertEqual(box.shadowOffset, Point(x: 0, y: MacOSControlMetrics.GroupBox.shadowOffsetY))
            XCTAssertEqual(box.shadowSpread, MacOSControlMetrics.GroupBox.shadowSpread)
            XCTAssertEqual(box.borderColor, palette.separator)
        }
    }
}
