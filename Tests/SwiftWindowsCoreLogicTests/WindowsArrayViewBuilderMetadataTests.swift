import Foundation
import SwiftWindowsCore
import SwiftWindowsUI
import XCTest

@testable import WinSwiftUI

@MainActor
final class WindowsArrayViewBuilderMetadataTests: XCTestCase {
    func testRawExpressionsKeepOriginalSlotsAndCountRepeatedNonemptyPrefixes() async throws {
        let leaf = AnyView(Text("row"))
        let expression = WindowsArrayViewBuilder.buildExpression([leaf, leaf])
        let single = WindowsArrayViewBuilder.buildExpression(Text("single"))
        let block = WindowsArrayViewBuilder.buildBlock([leaf])
        let fragment = try XCTUnwrap(block.first)
        let repeated = WindowsArrayViewBuilder.buildExpression([fragment, fragment])

        XCTAssertEqual(
            expression.map(\.structuralIdentity),
            [[.occurrence(0), .slot(0)], [.occurrence(0), .slot(1)]])
        XCTAssertEqual(single.map(\.structuralIdentity), [[]])
        XCTAssertEqual(
            repeated.map(\.structuralIdentity),
            [
                [.occurrence(0), .slot(0), .occurrence(0), .slot(0)],
                [.occurrence(1), .slot(0), .occurrence(0), .slot(0)],
            ])
        XCTAssertTrue(leaf.structuralIdentity.isEmpty)
        XCTAssertEqual(fragment.structuralIdentity, [.slot(0), .occurrence(0), .slot(0)])
    }

    func testBlocksKeepEmptyArgumentSlotsAndRepeatedFragmentOccurrences() async throws {
        let leaf = AnyView(Text("row"))
        let expression = WindowsArrayViewBuilder.buildExpression([leaf, leaf])
        let block = WindowsArrayViewBuilder.buildBlock([], expression, [])
        let first = try XCTUnwrap(block.first)
        let repeated = WindowsArrayViewBuilder.buildBlock([first, first])

        XCTAssertTrue(WindowsArrayViewBuilder.buildBlock().isEmpty)
        XCTAssertEqual(
            block.map(\.structuralIdentity),
            [
                [.slot(1), .occurrence(0), .occurrence(0), .slot(0)],
                [.slot(1), .occurrence(0), .occurrence(0), .slot(1)],
            ])
        XCTAssertEqual(
            repeated.map(\.structuralIdentity),
            [
                [.slot(0), .occurrence(0), .slot(1), .occurrence(0), .occurrence(0), .slot(0)],
                [.slot(0), .occurrence(1), .slot(1), .occurrence(0), .occurrence(0), .slot(0)],
            ])
    }

    func testBranchesAndLoopsPrependLiteralPrefixesWithoutRenumberingEmptyIterations() async {
        let block = WindowsArrayViewBuilder.buildBlock([AnyView(Text("row"))])
        let present = WindowsArrayViewBuilder.buildOptional(block)
        let absent = WindowsArrayViewBuilder.buildOptional(Optional<[AnyView]>.none)
        let first = WindowsArrayViewBuilder.buildEither(first: block)
        let second = WindowsArrayViewBuilder.buildEither(second: block)
        let loop = WindowsArrayViewBuilder.buildArray([present, absent, second])
        let available = WindowsArrayViewBuilder.buildLimitedAvailability(loop)

        XCTAssertTrue(absent.isEmpty)
        XCTAssertEqual(
            present.map(\.structuralIdentity), [[.branch(true), .slot(0), .occurrence(0), .slot(0)]])
        XCTAssertEqual(
            first.map(\.structuralIdentity), [[.branch(true), .slot(0), .occurrence(0), .slot(0)]])
        XCTAssertEqual(
            second.map(\.structuralIdentity), [[.branch(false), .slot(0), .occurrence(0), .slot(0)]])
        XCTAssertEqual(
            loop.map(\.structuralIdentity),
            [
                [.iteration(0), .branch(true), .slot(0), .occurrence(0), .slot(0)],
                [.iteration(2), .branch(false), .slot(0), .occurrence(0), .slot(0)],
            ])
        XCTAssertEqual(available.map(\.structuralIdentity), loop.map(\.structuralIdentity))
    }

    func testForEachExpressionAddsOnlyItsTypeAndContentScopeWithoutReevaluatingElements() async {
        let recorder = WindowsArrayMetadataRecorder()
        let rows = ForEach([7, 9], id: \.self) { index in
            recorder.elementCalls.append(String(index))
            return [AnyView(WindowsArrayMetadataLeaf(label: "row \(index)", recorder: recorder))]
        }
        let expression = WindowsArrayViewBuilder.buildExpression(rows)
        let forEachType = ObjectIdentifier(ForEach<[Int], Int>.self)

        XCTAssertEqual(
            expression.map(\.structuralIdentity),
            [
                [.view(forEachType), .role(.content), .keyed(.init(7)), .occurrence(0), .slot(0)],
                [.view(forEachType), .role(.content), .keyed(.init(9)), .occurrence(0), .slot(0)],
            ])
        XCTAssertEqual(recorder.elementCalls, ["7", "9"])
        XCTAssertTrue(recorder.leafBodies.isEmpty)
        let rendered = makeRoot(VStack(spacing: 0) { expression })
        defer { withExtendedLifetime(rendered.runtime) {} }

        XCTAssertEqual(rendered.node.children.map(\.text), ["row 7", "row 9"])
        XCTAssertEqual(rendered.node.children.map(\.dynamicContentIndex), [0, 1])
        XCTAssertEqual(rendered.node.children.map(\.nodeTag), ["7#0", "9#0"])
        XCTAssertEqual(recorder.elementCalls, ["7", "9"])
        XCTAssertEqual(recorder.leafBodies, ["row 7", "row 9"])
    }

    func testWindowsArraysInCanonicalForEachKeepElementIndicesAndRealEditCallbacks() async throws {
        let recorder = WindowsArrayMetadataRecorder()
        var deleted: [[Int]] = []
        var moved: [([Int], Int)] = []
        let rows = ForEach(["one", "two"], id: \.self) { element in
            let _ = recorder.elementCalls.append(element)
            windowsArrayMetadataRows(element, recorder: recorder)
        }
        .onDelete { deleted.append(Array($0)) }
        .onMove { moved.append((Array($0), $1)) }

        XCTAssertEqual(recorder.elementCalls, ["one", "two"])
        XCTAssertTrue(recorder.leafBodies.isEmpty)
        let rendered = makeRoot(VStack(spacing: 0) { rows })
        defer { withExtendedLifetime(rendered.runtime) {} }
        let nodes = rendered.node.children
        try assertMetadataContent(nodes)

        for node in nodes {
            let index = try XCTUnwrap(node.dynamicContentIndex)
            let delete = try XCTUnwrap(node.onDeleteRows)
            let move = try XCTUnwrap(node.onMoveRows)
            delete(IndexSet(integer: index))
            move(IndexSet(integer: index), 2)
        }

        XCTAssertEqual(deleted, [[0], [0], [1], [1]])
        XCTAssertEqual(moved.map { $0.0 }, [[0], [0], [1], [1]])
        XCTAssertEqual(moved.map { $0.1 }, [2, 2, 2, 2])
        XCTAssertEqual(recorder.elementCalls, ["one", "two"])
        XCTAssertEqual(
            recorder.leafBodies, ["one.single", "one.left", "one.right", "two.single", "two.left", "two.right"])
    }

    func testCanonicalSelectionListUsesOuterActivationAndInnerWindowsArrayEditOwners() async throws {
        let recorder = WindowsArrayMetadataRecorder()
        var selected: String? = "two.pair"
        var invalidations = 0
        var deleted: [[Int]] = []
        var moved: [([Int], Int)] = []
        let selection = Binding<String?>(get: { selected }, set: { selected = $0 })
        let content = ForEach(["one", "two"], id: \.self) { element in
            let _ = recorder.elementCalls.append(element)
            windowsArrayMetadataRows(element, recorder: recorder)
        }
        .onDelete { deleted.append(Array($0)) }
        .onMove { moved.append((Array($0), $1)) }
        let list = List(selection: selection) { content }

        XCTAssertEqual(recorder.elementCalls, ["one", "two"])
        XCTAssertTrue(recorder.leafBodies.isEmpty)
        let rendered = makeRoot(list, onInvalidate: { invalidations += 1 })
        defer { withExtendedLifetime(rendered.runtime) {} }
        let rows = rendered.node.children.filter { $0.accessibilityTraits.contains(.isSelectable) }
        XCTAssertEqual(rows.map(\.nodeTag), ["one#0", "one#1", "two#0", "two#1"])
        XCTAssertEqual(rows.map { $0.accessibilityTraits.contains(.isSelected) }, [false, false, false, true])
        let owners = try rows.map { row -> ViewNode in
            XCTAssertEqual(row.children.count, 1)
            return try XCTUnwrap(row.children.first)
        }
        try assertMetadataContent(owners)

        let firstPair = try XCTUnwrap(rows.dropFirst().first)
        let secondSingle = try XCTUnwrap(rows.dropFirst(2).first)
        let firstOwner = try XCTUnwrap(firstPair.children.first)
        let secondOwner = try XCTUnwrap(secondSingle.children.first)
        let activateFirst = try XCTUnwrap(firstPair.onActivate)
        let activateSecond = try XCTUnwrap(secondSingle.onActivate)
        activateFirst()
        XCTAssertEqual(selected, "one.pair")
        activateSecond()
        XCTAssertEqual(selected, "two.single")

        for owner in [firstOwner, secondOwner] {
            let index = try XCTUnwrap(owner.dynamicContentIndex)
            let delete = try XCTUnwrap(owner.onDeleteRows)
            let move = try XCTUnwrap(owner.onMoveRows)
            delete(IndexSet(integer: index))
            move(IndexSet(integer: index), 2)
        }

        XCTAssertEqual(invalidations, 2)
        XCTAssertEqual(deleted, [[0], [1]])
        XCTAssertEqual(moved.map { $0.0 }, [[0], [1]])
        XCTAssertEqual(moved.map { $0.1 }, [2, 2])
        XCTAssertEqual(recorder.elementCalls, ["one", "two"])
    }

    func testDataDrivenListTagsWindowsArrayRowsWithoutOpeningIDAndFrameBoundaries() async throws {
        let recorder = WindowsArrayMetadataRecorder()
        var selected: String? = "two"
        let selection = Binding<String?>(get: { selected }, set: { selected = $0 })
        let list = List(["one", "two"], id: \.self, selection: selection) { element in
            recorder.elementCalls.append(element)
            let prebuilt = windowsArrayMetadataRows(element, recorder: recorder)
            return prebuilt
        }

        XCTAssertEqual(recorder.elementCalls, ["one", "two"])
        XCTAssertTrue(recorder.leafBodies.isEmpty)
        let rendered = makeRoot(list)
        defer { withExtendedLifetime(rendered.runtime) {} }
        let rows = rendered.node.children.filter { $0.accessibilityTraits.contains(.isSelectable) }
        XCTAssertEqual(rows.map(\.nodeTag), ["one#0", "one#1", "two#0", "two#1"])
        XCTAssertEqual(rows.map { $0.accessibilityTraits.contains(.isSelected) }, [false, false, true, true])
        let owners = try rows.map { row -> ViewNode in
            XCTAssertEqual(row.children.count, 1)
            return try XCTUnwrap(row.children.first)
        }
        try assertMetadataContent(owners)

        let firstPair = try XCTUnwrap(rows.dropFirst().first)
        let activate = try XCTUnwrap(firstPair.onActivate)
        activate()
        XCTAssertEqual(selected, "one", "Data-driven List selection uses the element tag, not its leaf's tag.")
        XCTAssertEqual(recorder.elementCalls, ["one", "two"])
        XCTAssertEqual(
            recorder.leafBodies, ["one.single", "one.left", "one.right", "two.single", "two.left", "two.right"])
    }

    private func assertMetadataContent(
        _ nodes: [ViewNode], file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(nodes.count, 4, file: file, line: line)
        XCTAssertEqual(nodes.map(\.dynamicContentIndex), [0, 0, 1, 1], file: file, line: line)
        XCTAssertEqual(nodes.map(\.nodeTag), ["one#0", "one#1", "two#0", "two#1"], file: file, line: line)
        XCTAssertEqual(
            nodes.map(\.accessibilityIdentifier), ["one.single", "one.pair", "two.single", "two.pair"],
            file: file, line: line)
        let identities = try nodes.map { node -> RetainedViewIdentity in
            try XCTUnwrap(node.retainedViewIdentity, file: file, line: line)
        }
        XCTAssertEqual(Set(identities).count, 4, file: file, line: line)

        for (node, element) in zip(nodes.enumerated().filter { $0.offset % 2 == 1 }.map(\.element), ["one", "two"]) {
            XCTAssertEqual(
                allNodes(in: node).compactMap(\.text), ["\(element).left", "\(element).right"], file: file, line: line)
            let identity = try XCTUnwrap(node.retainedViewIdentity, file: file, line: line)
            XCTAssertTrue(identity.segments.contains(.explicit(.init("\(element).pair"))), file: file, line: line)
            XCTAssertFalse(
                nodes.contains {
                    $0.accessibilityIdentifier == "\(element).left" || $0.accessibilityIdentifier == "\(element).right"
                },
                file: file, line: line)
        }
    }

    private func makeRoot<Content: View>(
        _ view: Content, onInvalidate: @escaping () -> Void = {}
    ) -> (runtime: RetainedViewRuntime, node: ViewNode) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 400) }, invalidateHandler: onInvalidate)
        let node = AnyView(view).makeComponent(context: context).makeNode(runtime: runtime)
        return (runtime, node)
    }

    private func allNodes(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { allNodes(in: $0) }
    }
}

@MainActor
private final class WindowsArrayMetadataRecorder {
    var elementCalls: [String] = []
    var leafBodies: [String] = []
}

@MainActor
private struct WindowsArrayMetadataLeaf: View {
    let label: String
    let recorder: WindowsArrayMetadataRecorder

    var body: Text {
        let _ = recorder.leafBodies.append(label)
        Text(label)
    }
}

@MainActor
@WindowsArrayViewBuilder
private func windowsArrayMetadataRows(_ element: String, recorder: WindowsArrayMetadataRecorder) -> [AnyView] {
    WindowsArrayMetadataLeaf(label: "\(element).single", recorder: recorder)
        .accessibilityIdentifier("\(element).single")
        .tag("\(element).single")
    TupleView(
        (
            WindowsArrayMetadataLeaf(label: "\(element).left", recorder: recorder)
                .accessibilityIdentifier("\(element).left"),
            WindowsArrayMetadataLeaf(label: "\(element).right", recorder: recorder)
                .accessibilityIdentifier("\(element).right")
        )
    )
    .frame(width: 90, height: 30)
    .id("\(element).pair")
    .accessibilityIdentifier("\(element).pair")
    .tag("\(element).pair")
}
