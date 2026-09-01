import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// These assertions require the shared retained Button action owner. Raw saved
/// handlers test declaration lifetime separately from real input dispatch.
@MainActor
final class TableSortOwnershipTests: XCTestCase {
    func testCallbackReplacementRetainsTheButtonButRevokesItsOldDeclaration() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        let button = try fixture.button("name")
        let oldAction = try XCTUnwrap(button.onActivate)
        let oldID = try fixture.snapshot(named: "Name").id
        var replacements: [TableSortTestRequest] = []
        fixture.model.onSort = { key, order in replacements.append(.init(key: key, order: order)) }
        fixture.model.sort = ("name", .forward)
        fixture.reload()

        XCTAssertTrue(try fixture.button("name") === button)
        XCTAssertEqual(try fixture.snapshot(named: "Name").id, oldID)
        oldAction()
        XCTAssertTrue(fixture.model.requests.isEmpty)
        XCTAssertTrue(replacements.isEmpty)
        try fixture.click(try fixture.node("heading.name"))
        XCTAssertEqual(replacements, [.init(key: "name", order: .reverse)])
        XCTAssertTrue(fixture.model.requests.isEmpty)
    }

    func testClearingAndRestoringCallbackNeverReauthorizesOldButtonOrUIAIdentity() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        let oldButton = try fixture.button("name")
        let oldAction = try XCTUnwrap(oldButton.onActivate)
        let oldID = try fixture.snapshot(named: "Name").id
        let receiver = fixture.model.onSort
        fixture.model.onSort = nil
        fixture.reload()
        let passive = try fixture.header("name")
        XCTAssertTrue(fixture.nodes(in: passive).allSatisfy { $0.onActivate == nil })
        oldAction()
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: oldID))
        XCTAssertTrue(fixture.model.requests.isEmpty)

        fixture.model.onSort = receiver
        fixture.reload()
        XCTAssertFalse(try fixture.button("name") === oldButton)
        oldAction()
        oldButton.onActivate?()
        XCTAssertTrue(fixture.model.requests.isEmpty)
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: try fixture.snapshot(named: "Name").id))
        XCTAssertEqual(fixture.model.requests, [.init(key: "name", order: .forward)])
    }

    func testKeyedColumnReorderKeepsFocusAndUsesTheCurrentDirectionAndCallback() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        let name = try fixture.button("name")
        let number = try fixture.button("number")
        let oldNameAction = try XCTUnwrap(name.onActivate)
        let nameID = try fixture.snapshot(named: "Name").id
        fixture.runtime.requestFocus(name)
        fixture.model.columns.reverse()
        fixture.model.sort = ("name", .forward)
        fixture.reload()

        XCTAssertTrue(try fixture.button("name") === name)
        XCTAssertTrue(try fixture.button("number") === number)
        XCTAssertTrue(fixture.runtime.focusedNode === name)
        XCTAssertEqual(try fixture.snapshot(named: "Name").id, nameID)
        oldNameAction()
        XCTAssertTrue(fixture.model.requests.isEmpty)
        fixture.runtime.keyDown(KeyboardEvent(keyCode: 0x20, modifiers: []))
        try fixture.click(try fixture.node("heading.number"))
        XCTAssertEqual(
            fixture.model.requests,
            [.init(key: "name", order: .reverse), .init(key: "number", order: .forward)])
    }

    func testDuplicateKeyReorderKeepsOccurrenceOwnershipAndUpdatesEachVisibleLabel() async throws {
        let model = TableSortTestModel()
        model.columns = [
            TableSortTestColumn(id: "left", title: "Left label", key: "shared", authoredID: "left.label"),
            TableSortTestColumn(id: "right", title: "Right label", key: "shared", authoredID: "right.label"),
        ]
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        let firstOccurrence = try fixture.button("left")
        let secondOccurrence = try fixture.button("right")
        let firstIdentity = try XCTUnwrap(firstOccurrence.retainedViewIdentity)
        let secondIdentity = try XCTUnwrap(secondOccurrence.retainedViewIdentity)
        XCTAssertNotEqual(firstIdentity, secondIdentity)
        let oldFirst = try XCTUnwrap(firstOccurrence.onActivate)
        let oldSecond = try XCTUnwrap(secondOccurrence.onActivate)
        var labels: [String] = []
        model.onSort = { [weak fixture, weak model] key, order in
            guard let fixture, let model else { return }
            labels.append(fixture.runtime.focusedNode?.accessibilityLabel ?? "missing")
            model.requests.append(.init(key: key, order: order))
        }
        model.columns.reverse()
        model.sort = ("shared", .forward)
        fixture.reload()

        // Duplicate keys are distinguished by occurrence, not by a guessed
        // identity synthesized from the title or callback.
        XCTAssertTrue(try fixture.button("right") === firstOccurrence)
        XCTAssertTrue(try fixture.button("left") === secondOccurrence)
        XCTAssertEqual(firstOccurrence.retainedViewIdentity, firstIdentity)
        XCTAssertEqual(secondOccurrence.retainedViewIdentity, secondIdentity)
        XCTAssertEqual(firstOccurrence.accessibilityLabel, "Right label")
        XCTAssertEqual(secondOccurrence.accessibilityLabel, "Left label")
        oldFirst()
        oldSecond()
        XCTAssertTrue(model.requests.isEmpty)
        try fixture.click(try fixture.node("heading.right"))
        try fixture.click(try fixture.node("heading.left"))
        XCTAssertEqual(labels, ["Right label", "Left label"])
        XCTAssertEqual(model.requests, Array(repeating: .init(key: "shared", order: .reverse), count: 2))
    }

    func testAuthoredHeaderIDSurvivesDecorationSortChangesAndColumnReorder() async throws {
        let model = TableSortTestModel()
        model.columns[0].authoredID = "authored.name.header"
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        let button = try fixture.button("name")
        let content = try fixture.node("heading.name")
        let buttonIdentity = try XCTUnwrap(button.retainedViewIdentity)
        let contentIdentity = try XCTUnwrap(content.retainedViewIdentity)
        XCTAssertEqual(content.nodeTag, "authored.name.header")
        XCTAssertTrue(contentIdentity.segments.contains(.explicit(.init("authored.name.header"))))
        XCTAssertTrue(buttonIdentity.segments.contains(.role(.columnHeader)))
        XCTAssertTrue(buttonIdentity.segments.contains(.keyed(.init(AnyHashable("name")))))
        model.sort = ("name", .reverse)
        model.columns.reverse()
        fixture.reload()

        XCTAssertTrue(try fixture.button("name") === button)
        XCTAssertTrue(try fixture.node("heading.name") === content)
        XCTAssertEqual(button.retainedViewIdentity, buttonIdentity)
        XCTAssertEqual(content.retainedViewIdentity, contentIdentity)
        XCTAssertEqual(content.nodeTag, "authored.name.header")
    }

    func testNilKeysUseTheirPositionalSlotsWithoutAliasingOtherHeaders() async throws {
        let model = TableSortTestModel()
        model.columns = [
            TableSortTestColumn(id: "a", title: "Unkeyed A", key: nil),
            TableSortTestColumn(id: "b", title: "Unkeyed B", key: nil),
        ]
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        let first = try fixture.button("a")
        let second = try fixture.button("b")
        XCTAssertNotEqual(first.retainedViewIdentity, second.retainedViewIdentity)
        model.columns.reverse()
        fixture.reload()
        XCTAssertTrue(try fixture.button("b") === first)
        XCTAssertTrue(try fixture.button("a") === second)
        XCTAssertEqual(first.accessibilityLabel, "Unkeyed B")
        XCTAssertEqual(second.accessibilityLabel, "Unkeyed A")
        try fixture.click(try fixture.node("heading.b"))
        try fixture.click(try fixture.node("heading.a"))
        XCTAssertEqual(model.requests, Array(repeating: .init(key: nil, order: .forward), count: 2))
    }

    func testDistinctTypedKeysWithTheSameDescriptionDoNotShareHeaderIdentity() async throws {
        let model = TableSortTestModel()
        model.columns = [
            TableSortTestColumn(id: "integer", title: "Integer key", key: AnyHashable(7)),
            TableSortTestColumn(id: "string", title: "String key", key: AnyHashable("7")),
        ]
        let fixture = TableSortTestFixture(model: model)
        defer { fixture.close() }
        let integer = try fixture.button("integer")
        let string = try fixture.button("string")
        XCTAssertNotEqual(integer.retainedViewIdentity, string.retainedViewIdentity)
        model.columns.reverse()
        fixture.reload()
        XCTAssertTrue(try fixture.button("integer") === integer)
        XCTAssertTrue(try fixture.button("string") === string)
        try fixture.click(try fixture.node("heading.integer"))
        try fixture.click(try fixture.node("heading.string"))
        XCTAssertEqual(
            model.requests,
            [.init(key: AnyHashable(7), order: .forward), .init(key: AnyHashable("7"), order: .forward)])
    }

    func testRemovingAndReinsertingAColumnCreatesANewOwnerAndRetiresOldCallbacks() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        let removed = fixture.model.columns.removeFirst()
        let oldButton = try XCTUnwrap(try fixture.table().children.first?.children.first)
        let oldAction = try XCTUnwrap(oldButton.onActivate)
        let originalIdentity = oldButton.retainedViewIdentity
        fixture.reload()
        oldAction()
        XCTAssertTrue(fixture.model.requests.isEmpty)
        fixture.model.columns.insert(removed, at: 0)
        fixture.reload()
        let replacement = try fixture.button("name")
        XCTAssertFalse(replacement === oldButton)
        XCTAssertEqual(replacement.retainedViewIdentity, originalIdentity)
        oldAction()
        XCTAssertTrue(fixture.model.requests.isEmpty)
        try fixture.click(try fixture.node("heading.name"))
        XCTAssertEqual(fixture.model.requests, [.init(key: "name", order: .forward)])
    }

    func testSamePhysicalHeaderDetachAndReinsertDoesNotReviveItsEscapedAction() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        let header = try fixture.button("name")
        let parent = try XCTUnwrap(header.parent)
        let escaped = try XCTUnwrap(header.onActivate)
        parent.removeChild(header)
        parent.addChild(header)
        fixture.settle()
        escaped()
        header.onActivate?()
        fixture.runtime.requestFocus(header)
        fixture.runtime.keyDown(KeyboardEvent(keyCode: 0x20, modifiers: []))
        try fixture.click(header)
        for snapshot in fixture.source.uiaElementSnapshots() where snapshot.name == "Name" {
            _ = fixture.source.uiaInvokeDefaultAction(elementID: snapshot.id)
        }
        XCTAssertTrue(fixture.model.requests.isEmpty)
    }

    func testAReplacementDuringSortCannotReenterTheSamePhysicalButtonsActionFlight() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        var originalCalls = 0
        var replacementCalls = 0
        fixture.model.onSort = { [weak fixture] _, _ in
            guard let fixture else { return }
            originalCalls += 1
            fixture.model.sort = ("name", .forward)
            fixture.model.onSort = { _, _ in replacementCalls += 1 }
            fixture.reload()
            let current = try? fixture.button("name")
            current?.onActivate?()
        }
        fixture.reload()
        let button = try fixture.button("name")
        try fixture.click(try fixture.node("heading.name"))
        XCTAssertEqual(originalCalls, 1)
        XCTAssertEqual(replacementCalls, 0)
        XCTAssertTrue(try fixture.button("name") === button)
        fixture.key(0x20, on: button)
        XCTAssertEqual(originalCalls, 1)
        XCTAssertEqual(replacementCalls, 1)
    }

    func testRemovingTableDuringCallbackDoesNotRunStaleButtonInvalidation() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        var calls = 0
        fixture.model.onSort = { [weak fixture] _, _ in
            guard let fixture else { return }
            calls += 1
            fixture.model.isPresent = false
            fixture.host.reload()
        }
        fixture.reload()
        let oldAction = try XCTUnwrap(try fixture.button("name").onActivate)
        let builds = fixture.model.builds
        try fixture.click(try fixture.node("heading.name"))
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fixture.model.builds, builds + 1, "Only the author's removal rebuild is allowed")
        oldAction()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fixture.model.builds, builds + 1)
    }

    func testClosingTheHostRetiresRawAndUIAActionAuthority() async throws {
        let fixture = TableSortTestFixture()
        let header = try fixture.button("name")
        let escaped = try XCTUnwrap(header.onActivate)
        let id = try fixture.snapshot(named: "Name").id
        let builds = fixture.model.builds
        fixture.close()
        escaped()
        header.onActivate?()
        fixture.runtime.keyDown(KeyboardEvent(keyCode: 0x20, modifiers: []))
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertTrue(fixture.model.requests.isEmpty)
        XCTAssertEqual(fixture.model.builds, builds)
    }

    func testTwoWindowsWithTheSameKeysKeepIndependentSortCallbacksAndFocus() async throws {
        let first = TableSortTestFixture()
        let second = TableSortTestFixture()
        defer {
            first.close()
            second.close()
        }
        let firstButton = try first.button("name")
        let secondButton = try second.button("name")
        XCTAssertFalse(firstButton === secondButton)
        try first.click(try first.node("heading.name"))
        second.model.sort = ("name", .forward)
        second.reload()
        second.key(0x20, on: secondButton)
        XCTAssertEqual(first.model.requests, [.init(key: "name", order: .forward)])
        XCTAssertEqual(second.model.requests, [.init(key: "name", order: .reverse)])
        XCTAssertTrue(first.runtime.focusedNode === firstButton)
        XCTAssertTrue(second.runtime.focusedNode === secondButton)
    }

    func testHeaderConstructionRunsOncePerColumnAndDoesNotInvokeTheCallback() async throws {
        let fixture = TableSortTestFixture()
        defer { fixture.close() }
        XCTAssertEqual(fixture.model.headerBuilds, ["name": 1, "number": 1])
        XCTAssertTrue(fixture.model.requests.isEmpty)
        fixture.model.columns.reverse()
        fixture.model.sort = ("number", .reverse)
        fixture.reload()
        XCTAssertEqual(fixture.model.headerBuilds, ["name": 2, "number": 2])
        XCTAssertTrue(fixture.model.requests.isEmpty)
        XCTAssertEqual(fixture.model.rows.map(\.id), [2, 1])
    }
}
