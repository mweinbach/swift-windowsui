import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewThatFitsContainerTransparencyTests: XCTestCase {
    func testZStackAggregatesOnlyVisibleSelectedFillAxesThroughNestedBoundaries() async throws {
        var rootBuilds = 0
        let host = MountedOnChangeTestHost {
            rootBuilds += 1
            return AnyView(
                ZStack {
                    containerTransparencySelection(
                        Rectangle().frame(width: 7, height: 5)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("container.visible"))
                    containerTransparencySelection(
                        Rectangle().frame(width: 9, height: 6)
                            .frame(maxHeight: .infinity)
                            .hidden()
                            .accessibilityIdentifier("container.hidden"))
                }
                .accessibilityIdentifier("container.zstack"))
        }
        defer { host.close() }

        host.render()
        XCTAssertEqual(rootBuilds, 1)
        let stack = try containerTransparencyNode("container.zstack", in: host)
        let visible = try containerTransparencyNode("container.visible", in: host)
        let hidden = try containerTransparencyNode("container.hidden", in: host)
        let visibleBoundary = try containerTransparencyOuter(of: visible)
        let hiddenBoundary = try containerTransparencyOuter(of: hidden)
        XCTAssertEqual(visible.layoutFillAxes, .horizontalOnly)
        XCTAssertFalse(visible.isHidden)
        XCTAssertEqual(hidden.layoutFillAxes, .verticalOnly)
        XCTAssertTrue(hidden.isHidden)
        XCTAssertNil(stack.selectedContentRole)
        XCTAssertEqual(stack.layoutFillAxes, .horizontalOnly)
        XCTAssertEqual(stack.children.count, 2)
        XCTAssertTrue(stack.children.first === visibleBoundary)
        XCTAssertTrue(stack.children.last === hiddenBoundary)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testBothLazyGridAxesApplyFixedAndFlexibleSpecsToSelectedCellRoots() async throws {
        var rootBuilds = 0
        let host = MountedOnChangeTestHost {
            rootBuilds += 1
            return AnyView(
                VStack(spacing: 0) {
                    LazyVGrid(
                        columns: [GridItem(.fixed(40)), GridItem(.flexible(minimum: 20, maximum: 90))],
                        spacing: 0
                    ) {
                        containerTransparencySelection(
                            Rectangle().frame(height: 11)
                                .accessibilityIdentifier("container.v-fixed"))
                        containerTransparencySelection(
                            Rectangle().frame(minHeight: 13, maxHeight: 13)
                                .accessibilityIdentifier("container.v-flex"))
                    }
                    LazyHGrid(
                        rows: [GridItem(.fixed(30)), GridItem(.flexible(minimum: 15, maximum: 70))],
                        spacing: 0
                    ) {
                        containerTransparencySelection(
                            Rectangle().frame(width: 17)
                                .accessibilityIdentifier("container.h-fixed"))
                        containerTransparencySelection(
                            Rectangle().frame(minWidth: 19, maxWidth: 19)
                                .accessibilityIdentifier("container.h-flex"))
                    }
                })
        }
        defer { host.close() }

        host.render()
        XCTAssertEqual(rootBuilds, 1)
        let verticalFixed = try containerTransparencyNode("container.v-fixed", in: host)
        let verticalFlexible = try containerTransparencyNode("container.v-flex", in: host)
        let horizontalFixed = try containerTransparencyNode("container.h-fixed", in: host)
        let horizontalFlexible = try containerTransparencyNode("container.h-flex", in: host)
        _ = try containerTransparencyOuter(of: verticalFixed)
        _ = try containerTransparencyOuter(of: verticalFlexible)
        _ = try containerTransparencyOuter(of: horizontalFixed)
        _ = try containerTransparencyOuter(of: horizontalFlexible)
        XCTAssertEqual(verticalFixed.preferredSize, Size(width: 40, height: 11))
        XCTAssertEqual(horizontalFixed.preferredSize, Size(width: 17, height: 30))
        XCTAssertEqual(verticalFixed.flexItem, FlexProperties(grow: 0, shrink: 0))
        XCTAssertEqual(horizontalFixed.flexItem, FlexProperties(grow: 0, shrink: 0))
        XCTAssertNil(verticalFixed.layoutConstraints)
        XCTAssertNil(horizontalFixed.layoutConstraints)
        XCTAssertNil(verticalFlexible.preferredSize)
        XCTAssertNil(horizontalFlexible.preferredSize)
        XCTAssertEqual(verticalFlexible.flexItem, FlexProperties(flex: 1))
        XCTAssertEqual(horizontalFlexible.flexItem, FlexProperties(flex: 1))
        XCTAssertEqual(
            verticalFlexible.layoutConstraints,
            LayoutConstraints(minWidth: 20, maxWidth: 90, minHeight: 13, maxHeight: 13))
        XCTAssertEqual(
            horizontalFlexible.layoutConstraints,
            LayoutConstraints(minWidth: 19, maxWidth: 19, minHeight: 15, maxHeight: 70))
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testGroupedFormRoutesLabelPriorityAndRowClassificationThroughNestedBoundaries() async throws {
        var rootBuilds = 0
        let host = MountedOnChangeTestHost {
            rootBuilds += 1
            return AnyView(
                Form {
                    containerTransparencySelection(
                        LabeledContent {
                            Rectangle().frame(width: 14, height: 8)
                        } label: {
                            containerTransparencySelection(
                                Rectangle().frame(width: 20, height: 8)
                                    .layoutPriority(7)
                                    .accessibilityIdentifier("container.short-label"))
                        }
                        .accessibilityIdentifier("container.short-row"))
                    LabeledContent {
                        Rectangle().frame(width: 14, height: 8)
                    } label: {
                        Rectangle().frame(width: 60, height: 8)
                            .layoutPriority(11)
                            .accessibilityIdentifier("container.reference-label")
                    }
                    .accessibilityIdentifier("container.reference-row")
                    containerTransparencySelection(
                        Rectangle().frame(width: 10, height: 8)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("container.form-fill"))
                    containerTransparencySelection(
                        Rectangle().frame(width: 12, height: 8)
                            .accessibilityIdentifier("container.form-bare"))
                }
                .formStyle(.grouped)
                .accessibilityIdentifier("container.form"))
        }
        defer { host.close() }

        host.render()
        XCTAssertEqual(rootBuilds, 1)
        let form = try containerTransparencyNode("container.form", in: host)
        let shortRow = try containerTransparencyNode("container.short-row", in: host)
        let referenceRow = try containerTransparencyNode("container.reference-row", in: host)
        let shortLabel = try containerTransparencyNode("container.short-label", in: host)
        let referenceLabel = try containerTransparencyNode("container.reference-label", in: host)
        let fill = try containerTransparencyNode("container.form-fill", in: host)
        let bare = try containerTransparencyNode("container.form-bare", in: host)
        let shortRowBoundary = try containerTransparencyOuter(of: shortRow)
        let shortLabelBoundary = try containerTransparencyOuter(of: shortLabel)
        let fillBoundary = try containerTransparencyOuter(of: fill)
        let bareBoundary = try containerTransparencyOuter(of: bare)
        XCTAssertEqual(shortRow.formRowLabelChildIndex, 0)
        XCTAssertEqual(referenceRow.formRowLabelChildIndex, 0)
        XCTAssertEqual(shortRow.layoutFillAxes, .horizontalOnly)
        XCTAssertEqual(referenceRow.layoutFillAxes, .horizontalOnly)
        XCTAssertEqual(shortRow.children.count, 2)
        XCTAssertEqual(referenceRow.children.count, 2)
        let shortColumn = try XCTUnwrap(shortRow.children.first)
        let referenceColumn = try XCTUnwrap(referenceRow.children.first)
        XCTAssertEqual(shortColumn.children.count, 1)
        XCTAssertEqual(referenceColumn.children.count, 1)
        XCTAssertTrue(shortColumn.children.first === shortLabelBoundary)
        XCTAssertTrue(referenceColumn.children.first === referenceLabel)
        XCTAssertEqual(shortLabel.layoutPriority, 0)
        XCTAssertEqual(referenceLabel.layoutPriority, 0)
        XCTAssertEqual(shortColumn.preferredSize?.width, 60)
        XCTAssertEqual(referenceColumn.preferredSize?.width, 60)
        XCTAssertEqual(fill.layoutFillAxes, .horizontalOnly)
        XCTAssertEqual(bare.layoutFillAxes, LayoutFillAxes())
        XCTAssertEqual(form.children.count, 1)
        let formColumn = try XCTUnwrap(form.children.first)
        XCTAssertEqual(formColumn.children.count, 4)
        guard formColumn.children.count == 4 else { return }
        XCTAssertTrue(formColumn.children[0] === shortRowBoundary)
        XCTAssertTrue(formColumn.children[1] === referenceRow)
        XCTAssertTrue(formColumn.children[2] === fillBoundary)
        let indent = formColumn.children[3]
        XCTAssertNil(indent.selectedContentRole)
        XCTAssertEqual(indent.children.count, 1)
        XCTAssertTrue(indent.children.first === bareBoundary)
        XCTAssertTrue(bareBoundary.parent === indent)
        XCTAssertEqual(
            indent.layoutMode.stackLayout?.padding.leading,
            60 + MacOSControlMetrics.Form.labelColumnGap)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }
}

@MainActor
private func containerTransparencySelection<Content: View>(_ content: Content) -> some View {
    ViewThatFits(in: .horizontal) {
        ViewThatFits(in: .horizontal) { content }
    }
}

@MainActor
private func containerTransparencyOuter(
    of selected: ViewNode, file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    XCTAssertNil(selected.selectedContentRole, file: file, line: line)
    let inner = try XCTUnwrap(selected.parent, file: file, line: line)
    let outer = try XCTUnwrap(inner.parent, file: file, line: line)
    containerTransparencyAssertNeutralBoundary(inner, file: file, line: line)
    containerTransparencyAssertNeutralBoundary(outer, file: file, line: line)
    XCTAssertTrue(inner.children.first === selected, file: file, line: line)
    XCTAssertTrue(outer.children.first === inner, file: file, line: line)
    return outer
}

@MainActor
private func containerTransparencyAssertNeutralBoundary(
    _ boundary: ViewNode, file: StaticString, line: UInt
) {
    XCTAssertEqual(boundary.selectedContentRole, .viewThatFits, file: file, line: line)
    XCTAssertEqual(boundary.children.count, 1, file: file, line: line)
    XCTAssertNil(boundary.preferredSize, file: file, line: line)
    XCTAssertNil(boundary.layoutConstraints, file: file, line: line)
    XCTAssertEqual(boundary.flexItem, FlexProperties.default, file: file, line: line)
    XCTAssertEqual(boundary.layoutFillAxes, LayoutFillAxes(), file: file, line: line)
    XCTAssertNil(boundary.formRowLabelChildIndex, file: file, line: line)
    XCTAssertEqual(boundary.layoutPriority, 0, file: file, line: line)
    XCTAssertFalse(boundary.isHidden, file: file, line: line)
}

@MainActor
private func containerTransparencyNode(
    _ identifier: String, in host: MountedOnChangeTestHost,
    file: StaticString = #filePath, line: UInt = #line
) throws -> ViewNode {
    let matches = containerTransparencyDescendants(host.runtime.root).filter {
        $0.accessibilityIdentifier == identifier
    }
    XCTAssertEqual(matches.count, 1, file: file, line: line)
    return try XCTUnwrap(matches.first, file: file, line: line)
}

@MainActor
private func containerTransparencyDescendants(_ node: ViewNode) -> [ViewNode] {
    [node] + node.children.flatMap(containerTransparencyDescendants)
}
