import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// These fixtures exercise identity before reconciliation, not property-wrapper storage lifetime.
@MainActor
final class WinSwiftUIStructuralIdentityTests: XCTestCase {
    func testForEachKeepsDistinctIDsWithTheSameDescriptionAcrossReordering() async throws {
        var rows = [1, 2, 3].map(StructuralIdentityCollidingKey.init)
        let fixture = StructuralIdentityHost {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.self) { row in
                    Text("Row \(row.value)")
                        .accessibilityIdentifier("row.\(row.value)")
                }
                Text("Following sibling")
                    .accessibilityIdentifier("following")
            }
        }
        let before = try fixture.snapshots(["row.1", "row.2", "row.3", "following"])
        XCTAssertEqual(Set(before.values.map(\.identity)).count, 4)
        XCTAssertEqual(
            Set(before.filter { $0.key != "following" }.values.compactMap { $0.node.nodeTag }),
            Set(["shared#0"]),
            "Compatibility tags may collide; retained identity must still use Hashable equality")

        rows = [3, 1, 2].map(StructuralIdentityCollidingKey.init)
        fixture.reload()

        XCTAssertEqual(fixture.texts, ["Row 3", "Row 1", "Row 2", "Following sibling"])
        for (identifier, snapshot) in before {
            snapshot.assertRetained(as: try fixture.node(identifier))
        }
        XCTAssertEqual(try fixture.contentRoot().children.count, 4, "ForEach stays flattened in the stack")
    }

    func testAdjacentForEachWithOverlappingIDsKeepTheirOwnRows() async throws {
        var firstRows = [1, 2]
        var secondRows = [1, 2]
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                ForEach(firstRows, id: \.self) { row in
                    Text("First \(row)")
                        .accessibilityIdentifier("first.\(row)")
                }
                ForEach(secondRows, id: \.self) { row in
                    Text("Second \(row)")
                        .accessibilityIdentifier("second.\(row)")
                }
            }
        }
        let before = try fixture.snapshots(["first.1", "first.2", "second.1", "second.2"])
        XCTAssertEqual(Set(before.values.map(\.identity)).count, 4)
        XCTAssertEqual(try fixture.node("first.1").nodeTag, try fixture.node("second.1").nodeTag)

        firstRows = []
        secondRows = [2, 1]
        fixture.reload()

        XCTAssertEqual(fixture.texts, ["Second 2", "Second 1"])
        for identifier in ["second.1", "second.2"] {
            let snapshot = try XCTUnwrap(before[identifier])
            snapshot.assertRetained(as: try fixture.node(identifier))
        }
        XCTAssertEqual(try fixture.contentRoot().children.count, 2)
        XCTAssertFalse(fixture.contentNodes.contains { $0 === before["first.1"]?.node })
        XCTAssertFalse(fixture.contentNodes.contains { $0 === before["first.2"]?.node })
    }

    func testForEachMultipleChildrenKeepDistinctElementSlotsAfterReordering() async throws {
        var rows = [1, 2]
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                ForEach(rows, id: \.self) { row in
                    Text("Title \(row)")
                        .accessibilityIdentifier("title.\(row)")
                    Text("Detail \(row)")
                        .accessibilityIdentifier("detail.\(row)")
                }
            }
        }
        let before = try fixture.snapshots(["title.1", "detail.1", "title.2", "detail.2"])
        XCTAssertEqual(Set(before.values.map(\.identity)).count, 4)

        rows = [2, 1]
        fixture.reload()

        XCTAssertEqual(fixture.texts, ["Title 2", "Detail 2", "Title 1", "Detail 1"])
        for (identifier, snapshot) in before {
            snapshot.assertRetained(as: try fixture.node(identifier))
        }
        XCTAssertEqual(try fixture.node("title.2").nodeTag, "2#0")
        XCTAssertEqual(try fixture.node("detail.2").nodeTag, "2#1")
        XCTAssertEqual(try fixture.contentRoot().children.count, 4)
    }

    func testForEachOptionalChildPreservesFollowingSlotWhenItsCompatibilityTagChanges() async throws {
        var showsOptional = true
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                ForEach([1, 2], id: \.self) { row in
                    if showsOptional {
                        Text("Optional \(row)")
                            .accessibilityIdentifier("optional.\(row)")
                    }
                    Text("Following \(row)")
                        .accessibilityIdentifier("following.\(row)")
                }
            }
        }
        let before = try fixture.snapshots(["following.1", "following.2"])
        XCTAssertEqual(try fixture.node("following.1").nodeTag, "1#1")
        XCTAssertEqual(try fixture.node("following.2").nodeTag, "2#1")

        showsOptional = false
        fixture.reload()

        XCTAssertEqual(fixture.texts, ["Following 1", "Following 2"])
        for (identifier, snapshot) in before {
            snapshot.assertRetained(as: try fixture.node(identifier))
        }
        XCTAssertEqual(try fixture.node("following.1").nodeTag, "1#0")
        XCTAssertEqual(try fixture.node("following.2").nodeTag, "2#0")
        XCTAssertEqual(try fixture.contentRoot().children.count, 2)
    }

    func testErasedForEachKeepsKeyedRowsThroughChainedEditMetadataWrappers() async throws {
        var rows = [1, 2, 3]
        let fixture = StructuralIdentityHost {
            AnyView(
                ForEach(rows, id: \.self) { row in
                    Text("Row \(row)")
                        .accessibilityIdentifier("row.\(row)")
                }
                .onDelete { _ in }
                .onMove { _, _ in })
        }
        let before = try fixture.snapshots(["row.1", "row.2", "row.3"])
        XCTAssertEqual(Set(before.values.map(\.identity)).count, 3)
        for snapshot in before.values {
            XCTAssertNotNil(snapshot.node.onDeleteRows)
            XCTAssertNotNil(snapshot.node.onMoveRows)
        }

        rows = [3, 1, 2]
        fixture.reload()

        XCTAssertEqual(fixture.texts, ["Row 3", "Row 1", "Row 2"])
        for (identifier, snapshot) in before {
            snapshot.assertRetained(as: try fixture.node(identifier))
        }
        XCTAssertEqual(try fixture.node("row.3").dynamicContentIndex, 0)
        XCTAssertEqual(try fixture.node("row.1").dynamicContentIndex, 1)

        rows = [1, 2]
        fixture.reload()

        XCTAssertEqual(fixture.texts, ["Row 1", "Row 2"])
        for identifier in ["row.1", "row.2"] {
            let snapshot = try XCTUnwrap(before[identifier])
            snapshot.assertRetained(as: try fixture.node(identifier))
        }
    }

    func testSameTypeConditionalBranchesReplaceOnlyTheBranch() async throws {
        var usesFirstBranch = true
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                if usesFirstBranch {
                    Text("First branch")
                        .accessibilityIdentifier("branch")
                } else {
                    Text("Second branch")
                        .accessibilityIdentifier("branch")
                }
                Text("Following sibling")
                    .accessibilityIdentifier("following")
            }
        }
        let firstBranch = try StructuralIdentitySnapshot(fixture.node("branch"))
        let following = try StructuralIdentitySnapshot(fixture.node("following"))
        let container = try fixture.contentRoot()

        usesFirstBranch = false
        fixture.reload()

        let secondBranch = try fixture.node("branch")
        firstBranch.assertReplaced(by: secondBranch)
        XCTAssertEqual(secondBranch.text, "Second branch")
        following.assertRetained(as: try fixture.node("following"))
        XCTAssertTrue(try fixture.contentRoot() === container)
        XCTAssertEqual(container.children.count, 2, "Branch identity does not require a retained wrapper node")

        usesFirstBranch = true
        fixture.reload()

        let restoredBranch = try fixture.node("branch")
        XCTAssertEqual(restoredBranch.retainedViewIdentity, firstBranch.identity)
        XCTAssertFalse(restoredBranch === firstBranch.node, "A removed branch is a fresh node when it returns")
        XCTAssertFalse(restoredBranch === secondBranch)
        following.assertRetained(as: try fixture.node("following"))
    }

    func testAbsentOptionalPreservesFollowingSiblingAndRestoresItsStructuralSlot() async throws {
        var showsOptional = true
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                Text("Preceding sibling")
                    .accessibilityIdentifier("preceding")
                if showsOptional {
                    Text("Optional child")
                        .accessibilityIdentifier("optional")
                }
                Text("Following sibling")
                    .accessibilityIdentifier("following")
            }
        }
        let preceding = try StructuralIdentitySnapshot(fixture.node("preceding"))
        let optional = try StructuralIdentitySnapshot(fixture.node("optional"))
        let following = try StructuralIdentitySnapshot(fixture.node("following"))

        showsOptional = false
        fixture.reload()

        XCTAssertEqual(fixture.texts, ["Preceding sibling", "Following sibling"])
        XCTAssertEqual(try fixture.contentRoot().children.count, 2, "An absent builder child adds no placeholder")
        preceding.assertRetained(as: try fixture.node("preceding"))
        following.assertRetained(as: try fixture.node("following"))

        showsOptional = true
        fixture.reload()

        let restoredOptional = try fixture.node("optional")
        XCTAssertEqual(restoredOptional.retainedViewIdentity, optional.identity)
        XCTAssertFalse(restoredOptional === optional.node)
        preceding.assertRetained(as: try fixture.node("preceding"))
        following.assertRetained(as: try fixture.node("following"))
    }

    func testExplicitIDValueChangeResetsNodeWithoutChangingItsDescriptionTag() async throws {
        var key = StructuralIdentityCollidingKey(value: 1)
        var label = "Before"
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                Text(label)
                    .id(key)
                    .accessibilityIdentifier("explicit")
                Text("Following sibling")
                    .accessibilityIdentifier("following")
            }
        }
        let original = try StructuralIdentitySnapshot(fixture.node("explicit"))
        let following = try StructuralIdentitySnapshot(fixture.node("following"))
        XCTAssertEqual(original.node.nodeTag, "shared")

        label = "Updated without changing identity"
        fixture.reload()
        original.assertRetained(as: try fixture.node("explicit"))
        XCTAssertEqual(try fixture.node("explicit").text, label)

        key = StructuralIdentityCollidingKey(value: 2)
        fixture.reload()

        let replacement = try fixture.node("explicit")
        original.assertReplaced(by: replacement)
        XCTAssertEqual(replacement.nodeTag, "shared", "nodeTag remains the public description")
        following.assertRetained(as: try fixture.node("following"))
    }

    func testExplicitIDTypeChangeResetsNodesEvenWhenNumericKeysBridgeEqually() async throws {
        var content = structuralIdentityExplicitView(Int(7))
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                content
                Text("Following sibling")
                    .accessibilityIdentifier("following")
            }
        }
        let integer = try StructuralIdentitySnapshot(fixture.node("explicit"))
        let following = try StructuralIdentitySnapshot(fixture.node("following"))
        XCTAssertEqual(AnyHashable(Int(7)), AnyHashable(Int64(7)), "Typed identity must not rely on this equality")

        content = structuralIdentityExplicitView(Int64(7))
        fixture.reload()

        let integer64 = try StructuralIdentitySnapshot(fixture.node("explicit"))
        integer.assertReplaced(by: integer64.node)
        XCTAssertEqual(integer.node.nodeTag, "7")
        XCTAssertEqual(integer64.node.nodeTag, "7")
        following.assertRetained(as: try fixture.node("following"))

        content = structuralIdentityExplicitView("7")
        fixture.reload()

        let string = try fixture.node("explicit")
        integer64.assertReplaced(by: string)
        XCTAssertEqual(string.nodeTag, "7")
        following.assertRetained(as: try fixture.node("following"))
    }

    func testAnyViewReErasurePreservesGroupChildIdentityWithoutExtraLayoutNodes() async throws {
        var erased = AnyView(Text("Leaf").accessibilityIdentifier("leaf"))
        let fixture = StructuralIdentityHost {
            VStack(alignment: .leading, spacing: 7) {
                Group {
                    erased
                }
                Text("Following sibling")
                    .accessibilityIdentifier("following")
            }
        }
        let before = try fixture.snapshots(["leaf", "following"])
        let frames = fixture.contentNodes.map(\.resolvedFrame)
        let container = try fixture.contentRoot()
        XCTAssertEqual(container.children.count, 2)
        XCTAssertEqual(fixture.contentNodes.count, 3, "A single-child Group and type erasure add no layout nodes")

        erased = AnyView(AnyView(erased))
        fixture.reload()

        for (identifier, snapshot) in before {
            snapshot.assertRetained(as: try fixture.node(identifier))
        }
        XCTAssertTrue(try fixture.contentRoot() === container)
        XCTAssertEqual(fixture.contentNodes.count, 3)
        XCTAssertEqual(fixture.contentNodes.map(\.resolvedFrame), frames)
        guard case .stack(let layout) = container.layoutMode else {
            return XCTFail("Type erasure must preserve the stack layout mode")
        }
        XCTAssertEqual(layout, .vertical(spacing: 7, alignment: .leading))
    }

    func testReusedErasedViewHasIndependentStructuralOccurrences() async throws {
        let reused = AnyView(Text("Echo"))
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                Group { reused }
                Group { AnyView(reused) }
            }
        }
        let originals = try fixture.contentNodes.filter { $0.text == "Echo" }.map { try StructuralIdentitySnapshot($0) }
        XCTAssertEqual(originals.count, 2)
        XCTAssertEqual(Set(originals.map(\.identity)).count, 2)
        XCTAssertEqual(fixture.contentNodes.count, 3)

        fixture.reload()

        let rebuilt = fixture.contentNodes.filter { $0.text == "Echo" }
        XCTAssertEqual(rebuilt.count, 2)
        for (original, node) in zip(originals, rebuilt) {
            original.assertRetained(as: node)
        }
    }

    func testRepeatedPrebuiltArrayEntryGetsIndependentOccurrenceIdentities() async throws {
        let prebuilt = try XCTUnwrap(structuralIdentityPrebuiltRows("Echo", identifier: "echo").first)
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                [prebuilt, prebuilt]
            }
        }
        let originals = try fixture.contentNodes.filter { $0.text == "Echo" }.map { try StructuralIdentitySnapshot($0) }
        XCTAssertEqual(originals.count, 2)
        XCTAssertEqual(
            Set(originals.map(\.identity)).count, 2, "Existing builder metadata is not an occurrence identifier")
        XCTAssertEqual(fixture.contentNodes.count, 3)

        fixture.reload()

        let rebuilt = fixture.contentNodes.filter { $0.text == "Echo" }
        XCTAssertEqual(rebuilt.count, 2)
        for (original, node) in zip(originals, rebuilt) {
            original.assertRetained(as: node)
        }
    }

    func testExistingArrayClosuresAndDirectBuildBlockKeepIndependentOccurrences() async throws {
        let prebuilt = try XCTUnwrap(structuralIdentityPrebuiltRows("Echo", identifier: "echo").first)
        let existingContent: () -> [AnyView] = { [prebuilt, prebuilt] }
        let explicitBlockContent: () -> [AnyView] = { ViewBuilder.buildBlock([prebuilt, prebuilt]) }
        for content in [existingContent, explicitBlockContent] {
            let fixture = StructuralIdentityHost {
                VStack(spacing: 0, content: content)
            }
            let originals = try fixture.contentNodes.filter { $0.text == "Echo" }.map {
                try StructuralIdentitySnapshot($0)
            }
            XCTAssertEqual(originals.count, 2)
            XCTAssertEqual(Set(originals.map(\.identity)).count, 2)
            XCTAssertEqual(try fixture.contentRoot().children.count, 2)
            XCTAssertEqual(fixture.contentNodes.count, 3)

            fixture.reload()

            let rebuilt = fixture.contentNodes.filter { $0.text == "Echo" }
            XCTAssertEqual(rebuilt.count, 2)
            for (original, node) in zip(originals, rebuilt) {
                original.assertRetained(as: node)
            }
        }
    }

    func testConcatenatedBuilderArraysKeepDistinctOccurrencesWithoutLayoutWrappers() async throws {
        let leading = structuralIdentityPrebuiltRows("Leading array", identifier: "leading-array")
        let trailing = structuralIdentityPrebuiltRows("Trailing array", identifier: "trailing-array")
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                leading + trailing
            }
        }
        let before = try fixture.snapshots(["leading-array", "trailing-array"])
        XCTAssertEqual(Set(before.values.map(\.identity)).count, 2)
        XCTAssertEqual(fixture.texts, ["Leading array", "Trailing array"])
        XCTAssertEqual(try fixture.contentRoot().children.count, 2)
        XCTAssertEqual(fixture.contentNodes.count, 3)

        fixture.reload()

        for (identifier, snapshot) in before {
            snapshot.assertRetained(as: try fixture.node(identifier))
        }
    }

    func testOverlayAndBackgroundSeparatePrestructuredContentFromTheSameAuxiliaryViewType() async throws {
        for usesBackground in [false, true] {
            let base = structuralIdentityPrebuiltRows("Base", identifier: "base")
            let fixture = StructuralIdentityHost {
                if usesBackground {
                    return AnyView(
                        base.background {
                            Text("Auxiliary")
                                .accessibilityIdentifier("auxiliary")
                        })
                }
                return AnyView(
                    base.overlay {
                        Text("Auxiliary")
                            .accessibilityIdentifier("auxiliary")
                    })
            }
            let before = try fixture.snapshots(["base", "auxiliary"])
            XCTAssertEqual(
                Set(before.values.map(\.identity)).count, 2, "Content and auxiliary builders have separate roles")
            XCTAssertEqual(try fixture.contentRoot().children.count, 2)
            XCTAssertEqual(fixture.contentNodes.count, 3)
            XCTAssertEqual(fixture.texts, usesBackground ? ["Auxiliary", "Base"] : ["Base", "Auxiliary"])

            fixture.reload()

            for (identifier, snapshot) in before {
                snapshot.assertRetained(as: try fixture.node(identifier))
            }
        }
    }

    func testChangingTheConcreteViewInsideAnyViewReplacesItsNode() async throws {
        var content = AnyView(StructuralIdentityFirstLeaf())
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                content
                Text("Following sibling")
                    .accessibilityIdentifier("following")
            }
        }
        let original = try StructuralIdentitySnapshot(fixture.node("typed-leaf"))
        let following = try StructuralIdentitySnapshot(fixture.node("following"))

        content = AnyView(StructuralIdentitySecondLeaf())
        fixture.reload()

        let replacement = try fixture.node("typed-leaf")
        XCTAssertEqual(replacement.text, original.node.text, "Both view types produce the same retained text shape")
        original.assertReplaced(by: replacement)
        following.assertRetained(as: try fixture.node("following"))
    }

    func testSectionHeaderContentAndFooterUseDistinctStructuralRoles() async throws {
        var showsHeader = true
        let fixture = StructuralIdentityHost {
            Section {
                Text("Content")
                    .id("shared")
                    .accessibilityIdentifier("content")
            } header: {
                if showsHeader {
                    Text("Header")
                        .id("shared")
                        .accessibilityIdentifier("header")
                }
            } footer: {
                Text("Footer")
                    .id("shared")
                    .accessibilityIdentifier("footer")
            }
        }
        let before = try fixture.snapshots(["header", "content", "footer"])
        XCTAssertEqual(Set(before.values.map(\.identity)).count, 3)
        XCTAssertEqual(Set(before.values.compactMap { $0.node.nodeTag }), Set(["shared"]))
        XCTAssertEqual(try fixture.contentRoot().children.count, 3)

        showsHeader = false
        fixture.reload()

        XCTAssertEqual(fixture.texts, ["Content", "Footer"])
        XCTAssertEqual(try fixture.contentRoot().children.count, 2)
        for identifier in ["content", "footer"] {
            let snapshot = try XCTUnwrap(before[identifier])
            snapshot.assertRetained(as: try fixture.node(identifier))
        }
    }

    func testArrayAndLoopBuilderExpressionsStayFlatAndKeepFollowingSiblings() async throws {
        var extras = [
            AnyView(Text("Extra 0").accessibilityIdentifier("extra.0")),
            AnyView(Text("Extra 1").accessibilityIdentifier("extra.1")),
        ]
        var loopValues = [0, 1]
        let fixture = StructuralIdentityHost {
            VStack(spacing: 0) {
                structuralIdentityBuilderRows(extras: extras, loopValues: loopValues)
            }
        }
        let before = try fixture.snapshots(["preceding", "extra.0", "loop.0", "following"])
        XCTAssertEqual(
            fixture.texts, ["Preceding sibling", "Extra 0", "Extra 1", "Loop 0", "Loop 1", "Following sibling"])
        XCTAssertEqual(try fixture.contentRoot().children.count, 6)
        XCTAssertEqual(fixture.contentNodes.count, 7)
        let identities = try fixture.contentRoot().children.map { try XCTUnwrap($0.retainedViewIdentity) }
        XCTAssertEqual(Set(identities).count, 6)

        extras.removeLast()
        loopValues.removeLast()
        fixture.reload()

        XCTAssertEqual(fixture.texts, ["Preceding sibling", "Extra 0", "Loop 0", "Following sibling"])
        XCTAssertEqual(try fixture.contentRoot().children.count, 4)
        XCTAssertEqual(fixture.contentNodes.count, 5)
        for (identifier, snapshot) in before {
            snapshot.assertRetained(as: try fixture.node(identifier))
        }
    }
}

private struct StructuralIdentityCollidingKey: Hashable, CustomStringConvertible {
    let value: Int

    var description: String { "shared" }
}

private struct StructuralIdentityFirstLeaf: View {
    var body: some View {
        Text("Same retained shape")
            .accessibilityIdentifier("typed-leaf")
    }
}

private struct StructuralIdentitySecondLeaf: View {
    var body: some View {
        Text("Same retained shape")
            .accessibilityIdentifier("typed-leaf")
    }
}

@MainActor
private func structuralIdentityExplicitView<ID: Hashable>(_ id: ID) -> AnyView {
    AnyView(
        Text("Explicit identity")
            .id(id)
            .accessibilityIdentifier("explicit"))
}

@MainActor
@ViewBuilder
private func structuralIdentityPrebuiltRows(_ text: String, identifier: String) -> [AnyView] {
    Text(text)
        .accessibilityIdentifier(identifier)
}

@MainActor
@ViewBuilder
private func structuralIdentityBuilderRows(extras: [AnyView], loopValues: [Int]) -> [AnyView] {
    Text("Preceding sibling")
        .accessibilityIdentifier("preceding")
    extras
    for value in loopValues {
        Text("Loop \(value)")
            .accessibilityIdentifier("loop.\(value)")
    }
    Text("Following sibling")
        .accessibilityIdentifier("following")
}

@MainActor
private struct StructuralIdentitySnapshot {
    let node: ViewNode
    let identity: RetainedViewIdentity

    init(_ node: ViewNode, file: StaticString = #filePath, line: UInt = #line) throws {
        self.node = node
        self.identity = try XCTUnwrap(node.retainedViewIdentity, file: file, line: line)
    }

    func assertRetained(as rebuilt: ViewNode, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rebuilt.retainedViewIdentity, identity, file: file, line: line)
        XCTAssertTrue(
            rebuilt === node, "An unchanged structural occurrence keeps its retained node", file: file, line: line)
    }

    func assertReplaced(by rebuilt: ViewNode, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(rebuilt.retainedViewIdentity, file: file, line: line)
        XCTAssertNotEqual(rebuilt.retainedViewIdentity, identity, file: file, line: line)
        XCTAssertFalse(
            rebuilt === node, "A changed identity cannot update the previous node in place", file: file, line: line)
    }
}

@MainActor
private final class StructuralIdentityHost {
    let runtime: RetainedViewRuntime
    let host: ComponentHost

    init<Content: View>(_ content: @escaping @MainActor () -> Content) {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 400)))
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 400) },
            invalidateHandler: { [weak host] in host?.reload() })
        self.runtime = runtime
        self.host = host
        host.setComponents {
            [composeComponent(from: [AnyView(content())], context: context)]
        }
        _ = runtime.renderFrame()
    }

    var contentNodes: [ViewNode] {
        runtime.root.children.flatMap { descendants(in: $0) }
    }

    var texts: [String] {
        contentNodes.compactMap(\.text)
    }

    func reload() {
        host.reload()
        _ = runtime.renderFrame()
    }

    func contentRoot(file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        XCTAssertEqual(runtime.root.children.count, 1, file: file, line: line)
        return try XCTUnwrap(runtime.root.children.first, file: file, line: line)
    }

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = contentNodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one node identified as \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func snapshots(_ identifiers: [String]) throws -> [String: StructuralIdentitySnapshot] {
        var result: [String: StructuralIdentitySnapshot] = [:]
        for identifier in identifiers {
            result[identifier] = try StructuralIdentitySnapshot(node(identifier))
        }
        return result
    }

    private func descendants(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { descendants(in: $0) }
    }
}
