import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

/// The list's *row* children, skipping the hairline rules the default
/// style now interleaves between adjacent rows. Tests that index rows
/// positionally go through this so adding a separator does not renumber
/// every row assertion.
@MainActor
private func rows(of node: ViewNode) -> [ViewNode] {
    node.children.filter { $0.text != nil || !$0.children.isEmpty || $0.onActivate != nil }
}

/// The styled column inside a `Form`. A Form builds a centring box whose
/// only child is the ~640pt content column the sections live in; every
/// assertion about form chrome belongs to that child, not the box.
@MainActor
private func formContentColumn(of node: ViewNode) -> ViewNode {
    node.children[0]
}

@MainActor
private func makeListFormNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600),
    onInvalidate: @escaping () -> Void = {}
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: onInvalidate)
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func makeListFormRuntimeNode<V: View>(
    _ view: V,
    size: Size = Size(width: 800, height: 600),
    onInvalidate: @escaping () -> Void = {}
) -> (runtime: RetainedViewRuntime, node: ViewNode) {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: onInvalidate)
    let node = view.makeComponent(context: context).makeNode(runtime: runtime)
    node.frame = Rect(origin: .zero, size: size)
    runtime.root.addChild(node)
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    _ = runtime.renderFrame()
    return (runtime, node)
}

final class ListFormQualityTests: XCTestCase {
    // MARK: - Row metric stability

    func testSelectableRowsKeepConstantChromeMetricsAcrossSelectionStates() async {
        await MainActor.run {
            var selected: String? = "one"
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let node = makeListFormNode(
                List(selection: selection) {
                    Text("ONE").tag("one")
                    Text("TWO").tag("two")
                }
            )

            let selectedRow = rows(of: node)[0]
            let unselectedRow = rows(of: node)[1]

            // Padding stays constant so selection changes never shift row
            // metrics; macOS fills a selected row solid and draws no
            // border around it at all.
            XCTAssertEqual(selectedRow.borderWidth, 0)
            XCTAssertEqual(unselectedRow.borderWidth, 0)
            XCTAssertEqual(selectedRow.backgroundColor?.alpha ?? 0, 1, accuracy: 0.01)
            XCTAssertNil(unselectedRow.backgroundColor)
            guard
                case .stack(let selectedLayout) = selectedRow.layoutMode,
                case .stack(let unselectedLayout) = unselectedRow.layoutMode
            else {
                return XCTFail("Expected selectable rows to use retained stack layout")
            }
            XCTAssertEqual(selectedLayout, unselectedLayout)
            XCTAssertEqual(selectedRow.cornerRadius, unselectedRow.cornerRadius)
        }
    }

    func testSelectionBoundRowsApplyBuiltInMinimumHeight() async {
        await MainActor.run {
            var selected: String?
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let node = makeListFormNode(
                List(selection: selection) {
                    Text("ONE").tag("one")
                    Text("TWO").tag("two")
                }
            )

            XCTAssertEqual(rows(of: node)[0].layoutConstraints?.minHeight, 28)
            XCTAssertEqual(rows(of: node)[1].layoutConstraints?.minHeight, 28)
            XCTAssertEqual(rows(of: node)[0].layoutConstraints?.maxHeight, .infinity)
        }
    }

    func testExplicitDefaultMinListRowHeightOverridesBuiltInSelectionRowHeight() async {
        await MainActor.run {
            var selected: String?
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let node = makeListFormNode(
                List(selection: selection) {
                    Text("ONE").tag("one")
                }
                .environment(\.defaultMinListRowHeight, 44)
            )

            XCTAssertEqual(rows(of: node)[0].layoutConstraints?.minHeight, 44)
        }
    }

    func testPlainListRowsCarryTheMacOSRowHeight() async {
        await MainActor.run {
            let node = makeListFormNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
            )

            // Every row in a plain/automatic list is at least a standard
            // macOS row box tall (MacOSControlMetrics.List.plainRowHeight),
            // selection-bound or not — rows used to be exactly their label's
            // line box, which is what made an unselected list read as loose
            // text rather than a table.
            for index in 0..<2 {
                XCTAssertEqual(
                    rows(of: node)[index].layoutConstraints?.minHeight,
                    MacOSControlMetrics.List.plainRowHeight
                )
            }
        }
    }

    // MARK: - Selection and hover chrome

    func testSelectableRowsInstallHoverChromeThatTracksPointerThroughRuntime() async {
        await MainActor.run {
            var selected: String?
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let (runtime, node) = makeListFormRuntimeNode(
                List(selection: selection) {
                    Text("ONE").frame(height: 40).tag("one")
                    Text("TWO").frame(height: 40).tag("two")
                },
                size: Size(width: 320, height: 240)
            )

            let firstRow = rows(of: node)[0]
            let secondRow = rows(of: node)[1]
            XCTAssertEqual(firstRow.hoverEffect, .highlight)
            XCTAssertEqual(secondRow.hoverEffect, .highlight)
            XCTAssertFalse(firstRow.isHovered)
            XCTAssertFalse(secondRow.isHovered)

            // Rows are 52pt tall (40pt content + 12pt row padding).
            runtime.pointerMoved(to: Point(x: 20, y: 10))
            XCTAssertTrue(firstRow.isHovered)
            XCTAssertFalse(secondRow.isHovered)

            runtime.pointerMoved(to: Point(x: 20, y: 62))
            XCTAssertFalse(firstRow.isHovered)
            XCTAssertTrue(secondRow.isHovered)
        }
    }

    func testSelectionActivationStillRepaintsThroughInvalidation() async {
        await MainActor.run {
            var selected: String? = "one"
            var didInvalidate = false
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let node = makeListFormNode(
                List(selection: selection) {
                    Text("ONE").tag("one")
                    Text("TWO").tag("two")
                },
                onInvalidate: {
                    didInvalidate = true
                }
            )

            rows(of: node)[1].onActivate?()

            XCTAssertEqual(selected, "two")
            XCTAssertTrue(didInvalidate)
        }
    }

    // MARK: - Keyboard navigation

    func testArrowKeysMoveSingleSelectionAndFocusThroughRuntime() async {
        await MainActor.run {
            var selected: String? = "one"
            var didInvalidate = false
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let (runtime, node) = makeListFormRuntimeNode(
                List(selection: selection) {
                    Text("ONE").tag("one")
                    Text("TWO").tag("two")
                    Text("THREE").tag("three")
                },
                size: Size(width: 320, height: 240),
                onInvalidate: {
                    didInvalidate = true
                }
            )

            let firstRow = rows(of: node)[0]
            let secondRow = rows(of: node)[1]
            let thirdRow = rows(of: node)[2]

            runtime.requestFocus(firstRow)
            XCTAssertTrue(firstRow.isFocused)

            // Content fits the viewport, so the scroll panel cannot consume
            // the arrow key and it reaches the focused row's key handler.
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))

            XCTAssertEqual(selected, "two")
            XCTAssertTrue(didInvalidate)
            XCTAssertFalse(firstRow.isFocused)
            XCTAssertTrue(secondRow.isFocused)

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            XCTAssertEqual(selected, "three")
            XCTAssertTrue(thirdRow.isFocused)

            // At the bottom boundary the selection does not move.
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            XCTAssertEqual(selected, "three")
            XCTAssertTrue(thirdRow.isFocused)

            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
            XCTAssertEqual(selected, "two")
            XCTAssertTrue(secondRow.isFocused)
        }
    }

    func testArrowKeysSelectEdgeRowsWhenSelectionIsEmpty() async {
        await MainActor.run {
            var selected: String?
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let (_, node) = makeListFormRuntimeNode(
                List(selection: selection) {
                    Text("ONE").tag("one")
                    Text("TWO").tag("two")
                },
                size: Size(width: 320, height: 240)
            )

            rows(of: node)[0].onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            XCTAssertEqual(selected, "one")

            selected = nil
            rows(of: node)[0].onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
            XCTAssertEqual(selected, "two")
        }
    }

    func testArrowKeysKeepMovedSelectionScrolledIntoView() async {
        await MainActor.run {
            var selected: String? = "r1"
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let tags = ["r1", "r2", "r3", "r4", "r5"]
            let (_, node) = makeListFormRuntimeNode(
                List(tags, id: \.self, selection: selection) { tag in
                    Text(tag.uppercased())
                        .frame(height: 40)
                },
                size: Size(width: 320, height: 100)
            )

            // Five 52pt rows (40pt content + 12pt row padding) in a 100pt
            // viewport, with the default style's hairline rules between
            // them: content overflows, so keyboard-driven selection must
            // pull the target row into the visible window.
            XCTAssertEqual(node.scrollOffset, 0)

            for index in 0..<(tags.count - 1) {
                rows(of: node)[index].onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            }

            XCTAssertEqual(selected, "r5")
            // Four adjacencies between five rows, ruled with a
            // one-physical-pixel hairline each — except the pair either
            // side of the selected row, where the selection fill is the
            // boundary. Three rules at 1x.
            let contentBottom = 5.0 * 52.0 + 3.0
            XCTAssertEqual(node.scrollOffset, contentBottom - 100, accuracy: 0.5)

            for index in stride(from: tags.count - 1, through: 1, by: -1) {
                rows(of: node)[index].onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
            }

            XCTAssertEqual(selected, "r1")
            XCTAssertEqual(node.scrollOffset, 0, accuracy: 0.5)
        }
    }

    func testArrowKeysMoveSelectionInsteadOfScrollingOverflowingList() async {
        await MainActor.run {
            var selected: String? = "r1"
            let selection = Binding<String?>(
                get: { selected },
                set: { selected = $0 }
            )

            let tags = ["r1", "r2", "r3", "r4", "r5"]
            let (runtime, node) = makeListFormRuntimeNode(
                List(tags, id: \.self, selection: selection) { tag in
                    Text(tag.uppercased())
                        .frame(height: 40)
                },
                size: Size(width: 320, height: 100)
            )

            runtime.requestFocus(rows(of: node)[0])

            // Content overflows the viewport, but unmodified arrows must move
            // the selection rather than scroll the panel.
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))

            XCTAssertEqual(selected, "r2")
            XCTAssertTrue(rows(of: node)[1].isFocused)
            // Only scroll-into-view adjustment (if any), never a scroll step.
            XCTAssertEqual(node.scrollOffset, 4, accuracy: 0.5)
        }
    }

    func testArrowKeysLeaveMultipleSelectionUntouched() async {
        await MainActor.run {
            var selected: Set<String> = ["one", "two"]
            let selection = Binding<Set<String>>(
                get: { selected },
                set: { selected = $0 }
            )

            let node = makeListFormNode(
                List(selection: selection) {
                    Text("ONE").tag("one")
                    Text("TWO").tag("two")
                    Text("THREE").tag("three")
                }
            )

            rows(of: node)[0].onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            XCTAssertEqual(selected, ["one", "two"])
        }
    }

    // MARK: - Form and section grouping polish

    func testCardStyleFormsClipContentToRoundedCard() async {
        await MainActor.run {
            let automaticNode = makeListFormNode(
                Form {
                    Text("NAME")
                }
            )
            let groupedNode = makeListFormNode(
                Form {
                    Text("NAME")
                }
                .formStyle(.grouped)
            )
            let columnsNode = makeListFormNode(
                Form {
                    Text("NAME")
                }
                .formStyle(.columns)
            )

            // A Form is a *centred content column*: the node it builds is
            // the centring box, and the styled column is its only child.
            // macOS settings live in a ~640pt column with margins, so the
            // chrome can no longer be the outermost node.
            XCTAssertFalse(formContentColumn(of: automaticNode).clipsToBounds)
            XCTAssertTrue(formContentColumn(of: groupedNode).clipsToBounds)
            XCTAssertTrue(formContentColumn(of: columnsNode).clipsToBounds)
        }
    }

    func testSectionUsesTightGroupShadow() async {
        await MainActor.run {
            let node = makeListFormNode(
                Section {
                    Text("ROW")
                } header: {
                    Text("HEADER")
                }
            )

            XCTAssertEqual(node.shadowOffset, Point(x: 0, y: 8))
            XCTAssertEqual(node.shadowSpread, 4)
        }
    }

    func testFormStillHostsSectionsAsDistinctGroups() async {
        await MainActor.run {
            let node = makeListFormNode(
                Form {
                    Section("PROFILE") {
                        Text("NAME")
                    }
                    Section("ACTIONS") {
                        Text("SAVE")
                    }
                }
            )

            let column = formContentColumn(of: node)
            XCTAssertEqual(column.children.count, 2)
            // In a grouped form each section is a header *plus* a box, and
            // the header sits outside the box the way macOS System Settings
            // sets one — so the group chrome is now one level down.
            for section in rows(of: column) {
                XCTAssertEqual(section.sectionHeaderChildCount, 1)
                XCTAssertEqual(section.children.count, 2)
                let box = section.children[1]
                XCTAssertEqual(box.borderWidth, 1)
                XCTAssertGreaterThan(box.cornerRadius, 0)
            }
        }
    }
}
