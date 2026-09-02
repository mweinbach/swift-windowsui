import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ListImplicitSelectionTagTests: XCTestCase {
    func testDeclaredAnyHashableIDReplacesOnlyItsTypedTag() async throws {
        var selected: AnyHashable?
        let binding = Binding<AnyHashable?>(get: { selected }, set: { selected = $0 })
        let list = List([AnyHashable("outer")], id: \.self, selection: binding) { _ in
            Text("row").tag(AnyHashable("inner")).tag("unrelated")
        }
        let rendered = makeRoot(list)
        defer { withExtendedLifetime(rendered.runtime) {} }
        let nodes = contentNodes(in: rendered.node)
        XCTAssertEqual(nodes.count, 1)
        let values = try containerValues(in: XCTUnwrap(nodes.first))
        XCTAssertEqual(values.tag(for: AnyHashable.self), AnyHashable("outer"))
        XCTAssertEqual(values.tag(for: String.self), "unrelated")
        XCTAssertEqual(values.implicitSymbolTag, AnyHashable("outer"))
        let selectionRow = try XCTUnwrap(allNodes(in: rendered.node).first { $0.onActivate != nil })
        try XCTUnwrap(selectionRow.onActivate)()
        XCTAssertEqual(selected, AnyHashable("outer"))
    }

    func testOptionalIDPublishesNilAndNonNilUnderItsDeclaredType() async throws {
        let ids: [String?] = [nil, "outer"]
        let selection = Binding<Set<String?>>.constant(["outer"])
        let list = List(ids, id: \.self, selection: selection) { value in
            Text(value ?? "none").tag(Optional("inner")).tag("unrelated")
        }
        let rendered = makeRoot(list)
        defer { withExtendedLifetime(rendered.runtime) {} }
        let nodes = contentNodes(in: rendered.node)
        XCTAssertEqual(nodes.count, 2)
        let first = try containerValues(in: XCTUnwrap(nodes.first))
        let second = try containerValues(in: XCTUnwrap(nodes.dropFirst().first))
        XCTAssertEqual(first.tag(for: String?.self), .some(nil))
        XCTAssertEqual(second.tag(for: String?.self), .some(.some("outer")))
        XCTAssertEqual(first.tag(for: String.self), "unrelated")
        XCTAssertEqual(second.tag(for: String.self), "unrelated")
        XCTAssertEqual(first.implicitSymbolTag, AnyHashable(Optional<String>.none))
        XCTAssertEqual(second.implicitSymbolTag, AnyHashable(Optional("outer")))
    }

    func testExplicitNilSelectionStillPublishesTheElementTag() async throws {
        let single: Binding<String?>? = nil
        let multiple: Binding<Set<String>>? = nil
        let lists = [
            List(["outer"], id: \.self, selection: single) { _ in Text("row").tag("inner") },
            List(["outer"], id: \.self, selection: multiple) { _ in Text("row").tag("inner") },
        ]
        for list in lists {
            let rendered = makeRoot(list)
            defer { withExtendedLifetime(rendered.runtime) {} }
            let nodes = contentNodes(in: rendered.node)
            XCTAssertEqual(nodes.count, 1)
            XCTAssertEqual(try containerValues(in: XCTUnwrap(nodes.first)).tag(for: String.self), "outer")
            XCTAssertFalse(allNodes(in: rendered.node).contains { $0.accessibilityTraits.contains(.isSelectable) })
        }
    }

    func testIdentifiableSelectionInitializersPublishTheDeclaredElementTag() async throws {
        let data = [ListSelectionTagItem(id: AnyHashable("outer"))]
        let single = Binding<AnyHashable?>.constant(AnyHashable("outer"))
        let multiple = Binding<Set<AnyHashable>>.constant([AnyHashable("outer")])
        let lists = [
            List(data, selection: single) { _ in Text("row").tag(AnyHashable("inner")) },
            List(data, selection: multiple) { _ in Text("row").tag(AnyHashable("inner")) },
        ]
        for list in lists {
            let rendered = makeRoot(list)
            defer { withExtendedLifetime(rendered.runtime) {} }
            let nodes = contentNodes(in: rendered.node)
            XCTAssertEqual(nodes.count, 1)
            let values = try containerValues(in: XCTUnwrap(nodes.first))
            XCTAssertEqual(values.tag(for: AnyHashable.self), AnyHashable("outer"))
            XCTAssertNil(values.tag(for: String.self))
            XCTAssertEqual(
                allNodes(in: rendered.node).filter { $0.accessibilityTraits.contains(.isSelected) }.count, 1)
        }
    }

    func testRequiredRangeSelectionPublishesIntTags() async throws {
        let list = List(0..<2, selection: .constant(1)) { _ in Text("row").tag(-1) }
        let rendered = makeRoot(list)
        defer { withExtendedLifetime(rendered.runtime) {} }
        let nodes = contentNodes(in: rendered.node)
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(try nodes.map { try containerValues(in: $0).tag(for: Int.self) }, [0, 1])
        XCTAssertEqual(
            allNodes(in: rendered.node).filter { $0.accessibilityTraits.contains(.isSelectable) }
                .map { $0.accessibilityTraits.contains(.isSelected) },
            [false, true])
    }

    func testBindingDataSelectionPublishesTheElementTag() async throws {
        let data = Binding<[String]>.constant(["outer"])
        let selection = Binding<Set<String>>.constant(["outer"])
        let list = List(data, id: \.self, selection: selection) { _ in Text("row").tag("inner").tag(17) }
        let rendered = makeRoot(list)
        defer { withExtendedLifetime(rendered.runtime) {} }
        let nodes = contentNodes(in: rendered.node)
        XCTAssertEqual(nodes.count, 1)
        let values = try containerValues(in: XCTUnwrap(nodes.first))
        XCTAssertEqual(values.tag(for: String.self), "outer")
        XCTAssertEqual(values.tag(for: Int.self), 17)
    }

    func testNoSelectionInitializersPreserveAuthoredTypedTags() async throws {
        let items = [ListSelectionTagItem(id: "outer")]
        let lists = [
            List(["outer"], id: \.self) { _ in Text("row").tag("inner").tag(17) },
            List(items) { _ in Text("row").tag("inner").tag(17) },
            List(Binding<[String]>.constant(["outer"]), id: \.self) { _ in Text("row").tag("inner").tag(17) },
            List(Binding.constant(items)) { _ in Text("row").tag("inner").tag(17) },
        ]
        for list in lists {
            let rendered = makeRoot(list)
            defer { withExtendedLifetime(rendered.runtime) {} }
            let nodes = contentNodes(in: rendered.node)
            XCTAssertEqual(nodes.count, 1)
            let values = try containerValues(in: XCTUnwrap(nodes.first))
            XCTAssertEqual(values.tag(for: String.self), "inner")
            XCTAssertEqual(values.tag(for: Int.self), 17)
            XCTAssertEqual(values.implicitSymbolTag, AnyHashable("outer"))
            XCTAssertFalse(allNodes(in: rendered.node).contains { $0.accessibilityTraits.contains(.isSelectable) })
        }
    }

    func testBuilderSelectionPreservesTheAuthoredTag() async throws {
        let selection = Binding<String?>.constant("inner")
        let list = List(selection: selection) {
            ForEach(["outer"], id: \.self) { _ in Text("row").tag("inner") }
        }
        let rendered = makeRoot(list)
        defer { withExtendedLifetime(rendered.runtime) {} }
        let nodes = contentNodes(in: rendered.node)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(try containerValues(in: XCTUnwrap(nodes.first)).tag(for: String.self), "inner")
        XCTAssertEqual(allNodes(in: rendered.node).filter { $0.accessibilityTraits.contains(.isSelected) }.count, 1)
    }

    func testOverwrittenTagPayloadIsReleasedBeforeSourceValidation() async throws {
        let probe = ListSelectionTagReleaseProbe()
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 400, height: 400) }, invalidateHandler: {})
        let replacement = ListSelectionTagReleaseValue(value: 1, payload: nil)
        let result = List.materializedRow(
            AnyView(ListSelectionTagReleaseRow(probe: probe)), index: 0,
            implicitTag: AnyHashable(replacement), prefersImplicitTag: true,
            implicitTagType: ObjectIdentifier(ListSelectionTagReleaseValue.self), selectionMode: nil,
            listChrome: context.listStyle.retainedChrome(palette: context.controlPalette), isEditing: false,
            context: context, runtime: runtime,
            navigationState: ListKeyboardNavigationState(runtime: runtime, standalone: true),
            validateSource: {
                probe.validationReleases.append(probe.releases)
                return probe.releases == 0
            })
        defer { withExtendedLifetime(runtime) {} }
        XCTAssertEqual(probe.releases, 1)
        XCTAssertNil(probe.payload)
        XCTAssertEqual(probe.validationReleases.first, 0)
        XCTAssertEqual(probe.validationReleases.last, 1)
        let original = try XCTUnwrap(probe.node)
        XCTAssertEqual(try containerValues(in: original).tag(for: ListSelectionTagReleaseValue.self), replacement)
        XCTAssertFalse(result.node === original, "Reentrant tag cleanup must reject the stale content node")
    }

    private func makeRoot(_ list: List) -> (runtime: RetainedViewRuntime, node: ViewNode) {
        let size = Size(width: 400, height: 400)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
        let node = AnyView(list).makeComponent(context: context).makeNode(runtime: runtime)
        runtime.root.addChild(node)
        runtime.setRootSize(IntSize(width: 400, height: 400))
        node.frame = Rect(origin: .zero, size: size)
        _ = runtime.renderFrame()
        return (runtime, node)
    }

    private func containerValues(in node: ViewNode) throws -> ContainerValues {
        try XCTUnwrap(node.retainedContainerValues[retainedContainerValuesIdentifier()] as? ContainerValues)
    }

    private func contentNodes(in node: ViewNode) -> [ViewNode] {
        allNodes(in: node).filter { $0.dynamicContentIndex != nil }
    }

    private func allNodes(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { allNodes(in: $0) }
    }
}

private struct ListSelectionTagItem<ID: Hashable>: Identifiable {
    let id: ID
}

@MainActor
private final class ListSelectionTagReleaseProbe {
    var node: ViewNode?
    weak var payload: ListSelectionTagReleasePayload?
    var releases = 0
    var validationReleases: [Int] = []
}

@MainActor
private final class ListSelectionTagReleasePayload {
    let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

private struct ListSelectionTagReleaseValue: Hashable {
    let value: Int
    let payload: ListSelectionTagReleasePayload?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

@MainActor
private struct ListSelectionTagReleaseRow: View {
    typealias Body = Never
    let probe: ListSelectionTagReleaseProbe
    var body: Never { fatalError("Primitive test row has no body") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in makeTaggedNode() }
    }

    @inline(never)
    private func makeTaggedNode() -> ViewNode {
        let node = ViewNode()
        let payload = ListSelectionTagReleasePayload { probe.releases += 1 }
        probe.payload = payload
        var values = ContainerValues()
        values.setTag(ListSelectionTagReleaseValue(value: -1, payload: payload))
        node.retainedContainerValues[retainedContainerValuesIdentifier()] = values
        probe.node = node
        return node
    }
}
