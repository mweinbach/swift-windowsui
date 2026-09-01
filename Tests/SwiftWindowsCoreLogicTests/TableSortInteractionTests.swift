import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class TableSortInteractionTests: XCTestCase {
    func testPointerOnPassiveHeaderLabelInvokesOneSortAndFocusesItsButton() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        let button = try fixture.button("name")
        let label = try fixture.node("heading.name")
        XCTAssertNil(label.onActivate)
        XCTAssertFalse(label.isFocusable)
        XCTAssertEqual(fixture.nodes(in: button).filter { $0.onActivate != nil }.count, 1)

        try fixture.click(label)

        XCTAssertEqual(fixture.model.requests, [.init(key: "name", order: .forward)])
        XCTAssertTrue(fixture.runtime.focusedNode === button)
        XCTAssertTrue(try fixture.button("name") === button)
        XCTAssertEqual(fixture.model.selectionWrites, 0)
    }

    func testEnterAndSpaceUseTheCurrentAuthoredDirection() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        fixture.key(0x0D, on: try fixture.button("name"))
        fixture.model.sort = ("name", .forward)
        fixture.reload()
        fixture.key(0x20, on: try fixture.button("name"))
        fixture.model.sort = ("name", .reverse)
        fixture.reload()
        fixture.key(0x0D, on: try fixture.button("name"))

        XCTAssertEqual(
            fixture.model.requests,
            [
                .init(key: "name", order: .forward),
                .init(key: "name", order: .reverse),
                .init(key: "name", order: .forward),
            ])
    }

    func testUIAInvokeAndFocusUseTheRetainedButtonOwner() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        let button = try fixture.button("name")
        let snapshot = try fixture.snapshot(named: "Name")
        XCTAssertTrue(snapshot.isEnabled)
        XCTAssertTrue(snapshot.isKeyboardFocusable)
        XCTAssertTrue(snapshot.hasDefaultAction)
        XCTAssertEqual(snapshot.value, "Not sorted")
        XCTAssertEqual(snapshot.helpText, "Sort ascending")
        XCTAssertNil(snapshot.isSelected)
        XCTAssertTrue(fixture.source.uiaSetFocusResult(elementID: snapshot.id))
        XCTAssertTrue(fixture.runtime.focusedNode === button)

        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id))

        XCTAssertEqual(fixture.model.requests, [.init(key: "name", order: .forward)])
        XCTAssertEqual(try fixture.snapshot(named: "Name").id, snapshot.id)
        XCTAssertTrue(try fixture.snapshot(named: "Name").hasKeyboardFocus)
    }

    func testSortIndicatorAndAccessibleValueFollowDeclaredStateWithoutRenamingTheButton() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        for order in [WinSwiftUI.SortOrder.forward, .reverse] {
            fixture.model.sort = ("name", order)
            fixture.reload()
            let button = try fixture.button("name")
            let indicator = try XCTUnwrap(
                fixture.nodes(in: button).first { $0.text == (order == .forward ? " ▲" : " ▼") })
            XCTAssertTrue(indicator.isAccessibilityHidden)
            let snapshot = try fixture.snapshot(named: "Name")
            XCTAssertEqual(snapshot.value, order == .forward ? "Sorted ascending" : "Sorted descending")
            XCTAssertEqual(snapshot.helpText, order == .forward ? "Sort descending" : "Sort ascending")
            XCTAssertEqual(button.accessibilityLabel, "Name")
        }
        XCTAssertTrue(fixture.model.requests.isEmpty)
    }

    func testRepeatedRequestsDoNotMutateSortOrAutomaticallyReorderData() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        let before = fixture.model.rows
        let rows = Array(try fixture.table().children.dropFirst())
        try fixture.click(try fixture.node("heading.name"))
        try fixture.click(try fixture.node("heading.name"))

        XCTAssertEqual(fixture.model.requests, Array(repeating: .init(key: "name", order: .forward), count: 2))
        XCTAssertNil(fixture.model.sort)
        XCTAssertEqual(fixture.model.rows, before)
        let after = Array(try fixture.table().children.dropFirst())
        XCTAssertEqual(after.count, rows.count)
        for (old, current) in zip(rows, after) { XCTAssertTrue(current === old) }
        XCTAssertEqual(try fixture.snapshot(named: "Name").value, "Not sorted")
    }

    func testAnotherColumnsReverseSortDoesNotChangeTheDefaultRequestDirection() async throws {
        let model = TableSortTestModel()
        model.sort = ("number", .reverse)
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        try fixture.click(try fixture.node("heading.name"))

        XCTAssertEqual(model.requests, [.init(key: "name", order: .forward)])
        XCTAssertEqual(try fixture.snapshot(named: "Name").value, "Not sorted")
        XCTAssertEqual(try fixture.snapshot(named: "Number").value, "Sorted descending")
    }

    func testSortableColumnWithoutCallbackRemainsPassiveWithAnIndicator() async throws {
        let model = TableSortTestModel()
        model.onSort = nil
        model.sort = ("name", .forward)
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        let header = try fixture.header("name")
        XCTAssertFalse(header.isFocusable)
        XCTAssertTrue(fixture.nodes(in: header).allSatisfy { $0.onActivate == nil })
        XCTAssertTrue(fixture.nodes(in: header).contains { $0.text == " ▲" })
        try fixture.click(try fixture.node("heading.name"))
        let snapshots = fixture.source.uiaElementSnapshots().filter { $0.name == "Name" }
        XCTAssertFalse(snapshots.isEmpty)
        XCTAssertTrue(snapshots.allSatisfy { !$0.hasDefaultAction && !$0.isKeyboardFocusable })
        for snapshot in snapshots { XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id)) }
        XCTAssertTrue(model.requests.isEmpty)
    }

    func testNonsortableColumnIgnoresCallbackAndSortMetadata() async throws {
        let model = TableSortTestModel()
        model.columns[0].sortable = false
        model.sort = ("name", .reverse)
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        let header = try fixture.header("name")
        XCTAssertNil(header.onActivate)
        XCTAssertFalse(header.isFocusable)
        XCTAssertFalse(fixture.nodes(in: header).contains { $0.text == " ▼" })
        try fixture.click(try fixture.node("heading.name"))
        XCTAssertTrue(model.requests.isEmpty)
        XCTAssertEqual(model.selectionWrites, 0)
    }

    func testExplicitSortableNilKeyRequestsNilForwardAndNeverShowsAFalseSortedIndicator() async throws {
        let model = TableSortTestModel()
        model.columns = [TableSortTestColumn(id: "nil", title: "Unkeyed", key: nil)]
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        let initial = try fixture.snapshot(named: "Unkeyed")
        XCTAssertEqual(initial.value, "Not sorted")
        XCTAssertFalse(fixture.nodes(in: try fixture.button("nil")).contains { $0.text == " ▲" || $0.text == " ▼" })
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: initial.id))
        model.sort = ("another", .reverse)
        fixture.reload()
        fixture.key(0x20, on: try fixture.button("nil"))

        XCTAssertEqual(model.requests, Array(repeating: .init(key: nil, order: .forward), count: 2))
        XCTAssertEqual(try fixture.snapshot(named: "Unkeyed").value, "Not sorted")
    }

    func testDisabledHeaderHasNoPointerKeyboardOrUIAAction() async throws {
        let model = TableSortTestModel()
        model.isEnabled = false
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        let header = try fixture.header("name")
        XCTAssertNil(header.onActivate)
        XCTAssertNil(header.onRepeatActivate)
        XCTAssertFalse(header.isFocusable)
        let snapshot = try fixture.snapshot(named: "Name")
        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertFalse(snapshot.hasDefaultAction)
        XCTAssertFalse(snapshot.isKeyboardFocusable)
        try fixture.click(try fixture.node("heading.name"))
        fixture.runtime.requestFocus(header)
        fixture.runtime.keyDown(KeyboardEvent(keyCode: 0x20, modifiers: []))
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id))
        XCTAssertTrue(model.requests.isEmpty)

        model.isEnabled = true
        fixture.reload()
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: try fixture.snapshot(named: "Name").id))
        XCTAssertEqual(model.requests, [.init(key: "name", order: .forward)])
    }

    func testCustomAndExplicitlyEmptyHeaderLabelsNameTheButtonOwner() async throws {
        for label in ["Build number", ""] {
            let model = TableSortTestModel()
            model.columns = [TableSortTestColumn(id: "custom", title: "Visible", key: "custom", label: label)]
            let fixture = TableSortTestFixture(model: model)
            defer { fixture.close() }
            XCTAssertEqual(try fixture.button("custom").accessibilityLabel, label)
            let snapshot = try fixture.snapshot(named: label)
            XCTAssertTrue(snapshot.hasDefaultAction)
            XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id))
            XCTAssertEqual(model.requests, [.init(key: "custom", order: .forward)])
            XCTAssertNotNil(try fixture.node("heading.custom"))
        }
    }

    func testEmptyCustomHeaderUsesItsColumnTitleAndRemainsInvokable() async throws {
        let model = TableSortTestModel()
        model.columns = [
            TableSortTestColumn(id: "fallback", title: "Fallback", key: "fallback", emptyHeader: true)
        ]
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        let header = try fixture.button("fallback")
        XCTAssertTrue(fixture.nodes(in: header).contains { $0.text == "Fallback" })
        try fixture.click(header)
        XCTAssertEqual(model.requests, [.init(key: "fallback", order: .forward)])
        XCTAssertEqual(try fixture.snapshot(named: "Fallback").name, "Fallback")
    }

    func testFixedWidthsApplyToWholeHeaderControlsAndAlignWithUnselectedDataCells() async throws {
        let model = TableSortTestModel()
        model.hasSelection = false
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        for id in ["name", "number"] {
            let header = try fixture.button(id)
            let cell = try fixture.node("cell.\(id).2")
            let headerFrame = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: header))
            let cellFrame = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: cell))
            XCTAssertEqual(headerFrame.size.width, 160, accuracy: 0.001)
            XCTAssertEqual(cellFrame.size.width, 160, accuracy: 0.001)
            XCTAssertEqual(headerFrame.minX, cellFrame.minX, accuracy: 0.001)
            XCTAssertGreaterThan(headerFrame.size.height, 0)
        }
    }

    func testSingleSelectionRowsKeepTheirOwnOneActionAndSortingDoesNotSelectThem() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        let rows = Array(try fixture.table().children.dropFirst())
        XCTAssertEqual(rows.filter { $0.accessibilityTraits.contains(.isSelectable) }.count, 2)
        for row in rows { XCTAssertEqual(fixture.nodes(in: row).filter { $0.onActivate != nil }.count, 1) }
        try fixture.click(try fixture.node("cell.name.1"))
        XCTAssertEqual(fixture.model.selection, 1)
        XCTAssertEqual(fixture.model.selectionWrites, 1)
        try fixture.click(try fixture.node("heading.name"))
        XCTAssertEqual(fixture.model.selection, 1)
        XCTAssertEqual(fixture.model.selectionWrites, 1)
        XCTAssertEqual(fixture.model.requests, [.init(key: "name", order: .forward)])
    }

    func testMultipleSelectionInitializerAlsoRoutesSortWithoutWritingSelection() async throws {
        let model = TableSortTestModel()
        model.usesMultipleSelection = true
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        try fixture.click(try fixture.node("cell.name.1"))
        XCTAssertEqual(model.selections, [1, 2])
        XCTAssertEqual(model.selectionWrites, 1)
        fixture.key(0x0D, on: try fixture.button("number"))
        XCTAssertEqual(model.requests, [.init(key: "number", order: .forward)])
        XCTAssertEqual(model.selections, [1, 2])
        XCTAssertEqual(model.selectionWrites, 1)
    }

    func testPublicValueKeyPathColumnUsesTheExistingCallbackAPI() async throws {
        let model = TableSortTestModel()
        model.columns = [TableSortTestColumn(id: "name", title: "Name", key: "name")]
        let fixture = TableSortTestFixture(model: model) {
            AnyView(
                Table(model.rows, selection: Optional<Binding<Int?>>.none, sort: model.sort, onSort: model.onSort) {
                    TableColumn("Name", value: \TableSortTestRow.name, width: .fixed(160), sort: "name")
                }
                .accessibilityIdentifier("table.sort.fixture"))
        }
        defer { fixture.close() }
        let snapshot = try fixture.snapshot(named: "Name")
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id))
        XCTAssertEqual(model.requests, [.init(key: "name", order: .forward)])
        XCTAssertEqual(model.rows.map(\.name), ["Zulu", "Alpha"])
    }
}
