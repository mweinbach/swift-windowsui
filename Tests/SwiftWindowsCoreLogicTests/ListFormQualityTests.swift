import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

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

            let selectedRow = node.children[0]
            let unselectedRow = node.children[1]

            // Border width and padding stay constant so selection changes
            // never shift row metrics; only colors differ.
            XCTAssertEqual(selectedRow.borderWidth, 1)
            XCTAssertEqual(unselectedRow.borderWidth, 1)
            XCTAssertGreaterThan(selectedRow.borderColor.alpha, 0)
            XCTAssertEqual(unselectedRow.borderColor, .clear)
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

            XCTAssertEqual(node.children[0].layoutConstraints?.minHeight, 28)
            XCTAssertEqual(node.children[1].layoutConstraints?.minHeight, 28)
            XCTAssertEqual(node.children[0].layoutConstraints?.maxHeight, .infinity)
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

            XCTAssertEqual(node.children[0].layoutConstraints?.minHeight, 44)
        }
    }

    func testNonSelectionListRowsStayUnconstrained() async {
        await MainActor.run {
            let node = makeListFormNode(
                List {
                    Text("ONE")
                    Text("TWO")
                }
            )

            XCTAssertNil(node.children[0].layoutConstraints)
            XCTAssertNil(node.children[1].layoutConstraints)
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

            let firstRow = node.children[0]
            let secondRow = node.children[1]
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

            node.children[1].onActivate?()

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

            let firstRow = node.children[0]
            let secondRow = node.children[1]
            let thirdRow = node.children[2]

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

            node.children[0].onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            XCTAssertEqual(selected, "one")

            selected = nil
            node.children[0].onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
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
            // viewport: content overflows, so keyboard-driven selection must
            // pull the target row into the visible window.
            XCTAssertEqual(node.scrollOffset, 0)

            for index in 0..<(tags.count - 1) {
                node.children[index].onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            }

            XCTAssertEqual(selected, "r5")
            let contentBottom = 5.0 * 52.0
            XCTAssertEqual(node.scrollOffset, contentBottom - 100, accuracy: 0.5)

            for index in stride(from: tags.count - 1, through: 1, by: -1) {
                node.children[index].onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
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

            runtime.requestFocus(node.children[0])

            // Content overflows the viewport, but unmodified arrows must move
            // the selection rather than scroll the panel.
            runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))

            XCTAssertEqual(selected, "r2")
            XCTAssertTrue(node.children[1].isFocused)
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

            node.children[0].onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
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

            XCTAssertFalse(automaticNode.clipsToBounds)
            XCTAssertTrue(groupedNode.clipsToBounds)
            XCTAssertTrue(columnsNode.clipsToBounds)
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

            XCTAssertEqual(node.children.count, 2)
            XCTAssertEqual(node.children[0].sectionHeaderChildCount, 1)
            XCTAssertEqual(node.children[1].sectionHeaderChildCount, 1)
            XCTAssertEqual(node.children[0].borderWidth, 1)
            XCTAssertEqual(node.children[1].borderWidth, 1)
            XCTAssertGreaterThan(node.children[0].cornerRadius, 0)
            XCTAssertGreaterThan(node.children[1].cornerRadius, 0)
        }
    }
}
