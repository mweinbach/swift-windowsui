import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class CanonicalViewBuilderMetadataTests: XCTestCase {
    func testInheritedBodyBuildsTaggedForEachChildrenWithoutEvaluatingLeafBodies() async {
        let recorder = CanonicalMetadataRecorder()
        let view = CanonicalMetadataInheritedRows(recorder: recorder)
        XCTAssertEqual(recorder.rootBodyCalls, 0)
        XCTAssertTrue(recorder.elementCalls.isEmpty)
        XCTAssertTrue(recorder.leafBodies.isEmpty)

        let rows = view.body

        XCTAssertEqual(recorder.rootBodyCalls, 1)
        assertPairRows(rows, recorder: recorder)
        XCTAssertEqual(recorder.rootBodyCalls, 1)
    }

    func testTypedTupleKeepsTagsAndElementIndicesThroughForEachDecoration() async {
        let recorder = CanonicalMetadataRecorder()
        let rows = ForEach(["one", "two"], id: \.self) { element in
            let _ = recorder.elementCalls.append(element)
            TupleView(
                (
                    canonicalMetadataLeaf(element, part: "a", recorder: recorder),
                    canonicalMetadataLeaf(element, part: "b", recorder: recorder)
                ))
        }

        assertPairRows(rows, recorder: recorder)
    }

    func testExplicitReturnOfReErasedTupleKeepsEachLeafMetadata() async {
        let recorder = CanonicalMetadataRecorder()
        let rows = ForEach(["one", "two"], id: \.self) { element in
            recorder.elementCalls.append(element)
            let tuple = TupleView(
                (
                    canonicalMetadataLeaf(element, part: "a", recorder: recorder),
                    canonicalMetadataLeaf(element, part: "b", recorder: recorder)
                ))
            return [AnyView(AnyView(tuple))]
        }

        assertPairRows(rows, recorder: recorder)
    }

    func testPrebuiltErasedTupleArrayIsProjectedBeforeElementDecoration() async {
        let recorder = CanonicalMetadataRecorder()
        let tuple = TupleView(
            (
                canonicalMetadataLeaf("shared", part: "a", recorder: recorder),
                canonicalMetadataLeaf("shared", part: "b", recorder: recorder)
            ))
        let prebuilt: [AnyView] = [AnyView(tuple)]
        let rows = ForEach(["one", "two"], id: \.self) { element in
            let _ = recorder.elementCalls.append(element)
            prebuilt
        }

        assertPairRows(
            rows, recorder: recorder,
            labels: ["shared.a", "shared.b", "shared.a", "shared.b"])
    }

    func testErasedGroupProjectsItsTypedChildrenWithoutOpeningTheirBodies() async {
        let recorder = CanonicalMetadataRecorder()
        let rows = ForEach(["one", "two"], id: \.self) { element in
            recorder.elementCalls.append(element)
            return [
                AnyView(
                    Group {
                        canonicalMetadataLeaf(element, part: "a", recorder: recorder)
                        canonicalMetadataLeaf(element, part: "b", recorder: recorder)
                    })
            ]
        }

        assertPairRows(rows, recorder: recorder)
    }

    func testErasedTupleRowsWithCollidingIDDescriptionsRetainNodesAcrossReordering() async throws {
        var elements = [CanonicalMetadataCollidingID(value: 1), CanonicalMetadataCollidingID(value: 2)]
        let fixture = CanonicalMetadataHost {
            VStack(spacing: 0) {
                ForEach(elements, id: \.self) { element in
                    let tuple = TupleView(
                        (
                            Text("\(element.value).a").accessibilityIdentifier("\(element.value).a"),
                            Text("\(element.value).b").accessibilityIdentifier("\(element.value).b")
                        ))
                    return [AnyView(AnyView(tuple))]
                }
                Text("following").accessibilityIdentifier("following")
            }
        }
        let identifiers = ["1.a", "1.b", "2.a", "2.b", "following"]
        let before = try identifiers.map { try fixture.node($0) }
        let beforeIdentities = try before.map { try XCTUnwrap($0.retainedViewIdentity) }
        XCTAssertEqual(Set(beforeIdentities).count, 5)
        XCTAssertEqual(before.prefix(4).map(\.nodeTag), ["shared#0", "shared#1", "shared#0", "shared#1"])

        elements.reverse()
        fixture.reload()

        XCTAssertEqual(try fixture.contentRoot().children.map(\.text), ["2.a", "2.b", "1.a", "1.b", "following"])
        for (index, identifier) in identifiers.enumerated() {
            let retained = try fixture.node(identifier)
            XCTAssertTrue(retained === before[index])
            XCTAssertEqual(retained.retainedViewIdentity, beforeIdentities[index])
        }
        let reordered = try ["2.a", "2.b", "1.a", "1.b"].map { try fixture.node($0) }
        XCTAssertEqual(reordered.map(\.dynamicContentIndex), [0, 0, 1, 1])
        XCTAssertEqual(
            reordered.map { node -> Int? in
                let values = node.retainedContainerValues[retainedContainerValuesIdentifier()] as? ContainerValues
                return (values?.implicitSymbolTag?.base as? CanonicalMetadataCollidingID)?.value
            },
            [2, 2, 1, 1])
    }

    func testRemovingAnOptionalTupleLeafKeepsFollowingLeafAndOuterSiblingIdentity() async throws {
        var includesOptional = true
        let fixture = CanonicalMetadataHost {
            VStack(spacing: 0) {
                ForEach(["one", "two"], id: \.self) { element in
                    let optional: AnyView? =
                        includesOptional
                        ? AnyView(Text("\(element).optional").accessibilityIdentifier("\(element).optional"))
                        : nil
                    let tuple = TupleView(
                        (
                            optional,
                            Text("\(element).following").accessibilityIdentifier("\(element).following")
                        ))
                    return [AnyView(tuple)]
                }
                Text("following").accessibilityIdentifier("following")
            }
        }
        let identifiers = ["one.following", "two.following", "following"]
        let before = try identifiers.map { try fixture.node($0) }
        let identities = try before.map { try XCTUnwrap($0.retainedViewIdentity) }
        XCTAssertEqual(before.prefix(2).map(\.nodeTag), ["one#1", "two#1"])

        includesOptional = false
        fixture.reload()

        XCTAssertEqual(try fixture.contentRoot().children.map(\.text), identifiers)
        for (index, identifier) in identifiers.enumerated() {
            let node = try fixture.node(identifier)
            XCTAssertTrue(node === before[index])
            XCTAssertEqual(node.retainedViewIdentity, identities[index])
        }
        XCTAssertEqual(before.prefix(2).map(\.nodeTag), ["one#0", "two#0"])
        XCTAssertEqual(before.prefix(2).map(\.dynamicContentIndex), [0, 1])
        XCTAssertFalse(fixture.nodes.contains { $0.accessibilityIdentifier?.hasSuffix(".optional") == true })
    }

    func testEachProjectedLeafInvokesRealEditCallbacksWithItsElementIndex() async throws {
        let recorder = CanonicalMetadataRecorder()
        var deleted: [[Int]] = []
        var moved: [([Int], Int)] = []
        let rows = ForEach(["one", "two"], id: \.self) { element in
            recorder.elementCalls.append(element)
            return [
                AnyView(
                    TupleView(
                        (
                            canonicalMetadataLeaf(element, part: "a", recorder: recorder),
                            canonicalMetadataLeaf(element, part: "b", recorder: recorder)
                        )))
            ]
        }
        .onDelete { deleted.append(Array($0)) }
        .onMove { moved.append((Array($0), $1)) }
        XCTAssertEqual(
            rows.contentViews.map { $0.selectionTag?.base as? String }, ["one.a", "one.b", "two.a", "two.b"])
        XCTAssertTrue(recorder.leafBodies.isEmpty)
        let rendered = makeRoot(VStack(spacing: 0) { rows })
        defer { withExtendedLifetime(rendered.runtime) {} }
        let nodes = rendered.node.children
        XCTAssertEqual(nodes.count, 4)
        XCTAssertEqual(nodes.map(\.dynamicContentIndex), [0, 0, 1, 1])
        XCTAssertEqual(nodes.map(\.nodeTag), ["one#0", "one#1", "two#0", "two#1"])

        for node in nodes {
            let index = try XCTUnwrap(node.dynamicContentIndex)
            let delete = try XCTUnwrap(node.onDeleteRows)
            let move = try XCTUnwrap(node.onMoveRows)
            delete(IndexSet(integer: index))
            move(IndexSet(integer: index), 0)
        }

        XCTAssertEqual(deleted, [[0], [0], [1], [1]])
        XCTAssertEqual(moved.map { $0.0 }, [[0], [0], [1], [1]])
        XCTAssertEqual(moved.map { $0.1 }, [0, 0, 0, 0])
        XCTAssertEqual(recorder.elementCalls, ["one", "two"])
        XCTAssertEqual(recorder.leafBodies, ["one.a", "one.b", "two.a", "two.b"])
    }

    func testNilEditOverridesClearHandlersOnRetainedProjectedRows() async throws {
        var enablesEditing = true
        var deleteCalls = 0
        var moveCalls = 0
        let delete: (IndexSet) -> Void = { _ in deleteCalls += 1 }
        let move: (IndexSet, Int) -> Void = { _, _ in moveCalls += 1 }
        let fixture = CanonicalMetadataHost {
            VStack(spacing: 0) {
                ForEach(["one", "two"], id: \.self) { element in
                    return [
                        AnyView(
                            TupleView(
                                (
                                    Text("\(element).a").accessibilityIdentifier("\(element).a"),
                                    Text("\(element).b").accessibilityIdentifier("\(element).b")
                                )))
                    ]
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
                .onDelete(perform: enablesEditing ? delete : nil)
                .onMove(perform: enablesEditing ? move : nil)
            }
        }
        let identifiers = ["one.a", "one.b", "two.a", "two.b"]
        let before = try identifiers.map { try fixture.node($0) }
        let identities = try before.map { try XCTUnwrap($0.retainedViewIdentity) }
        for node in before {
            let index = try XCTUnwrap(node.dynamicContentIndex)
            let deleteHandler = try XCTUnwrap(node.onDeleteRows)
            let moveHandler = try XCTUnwrap(node.onMoveRows)
            deleteHandler(IndexSet(integer: index))
            moveHandler(IndexSet(integer: index), 0)
        }
        XCTAssertEqual(deleteCalls, 4)
        XCTAssertEqual(moveCalls, 4)

        enablesEditing = false
        fixture.reload()

        for (index, identifier) in identifiers.enumerated() {
            let node = try fixture.node(identifier)
            XCTAssertTrue(node === before[index])
            XCTAssertEqual(node.retainedViewIdentity, identities[index])
            XCTAssertNil(node.onDeleteRows)
            XCTAssertNil(node.onMoveRows)
        }
        XCTAssertEqual(before.map(\.dynamicContentIndex), [0, 0, 1, 1])
        XCTAssertEqual(deleteCalls, 4)
        XCTAssertEqual(moveCalls, 4)
    }

    func testErasedTuplePreservesImplicitFirstLeafAndExplicitSecondLeafScrollTargets() async throws {
        var proxy: ScrollViewProxy?
        let view = ScrollViewReader { readerProxy in
            let _ = { proxy = readerProxy }()
            ScrollView {
                ForEach(0..<12, id: \.self) { element in
                    return [
                        AnyView(
                            TupleView(
                                (
                                    Text("\(element).first").frame(height: 20),
                                    Text("\(element).second").frame(height: 30).id("explicit-\(element)")
                                )))
                    ]
                }
            }
        }
        let size = Size(width: 120, height: 100)
        let rendered = makeRoot(view, size: size)
        defer { withExtendedLifetime(rendered.runtime) {} }
        rendered.runtime.root.addChild(rendered.node)
        rendered.node.frame = Rect(origin: .zero, size: size)
        rendered.runtime.setRootSize(IntSize(width: 120, height: 100))
        _ = rendered.runtime.renderScene()
        let reader = try XCTUnwrap(proxy)
        XCTAssertEqual(rendered.node.scrollAxis, .vertical)
        let first = try XCTUnwrap(allNodes(in: rendered.node).first { $0.nodeTag == "8#0" })
        let second = try XCTUnwrap(allNodes(in: rendered.node).first { $0.nodeTag == "8#1" })
        XCTAssertFalse(first === second)
        XCTAssertEqual(first.dynamicContentIndex, 8)
        XCTAssertEqual(second.dynamicContentIndex, 8)
        let firstTargets = first.retainedPreferenceValues.values.compactMap { $0 as? RetainedScrollTargetIdentity }
        let secondTargets = second.retainedPreferenceValues.values.compactMap { $0 as? RetainedScrollTargetIdentity }
        XCTAssertTrue(firstTargets.contains { $0.identifier == "8" && $0.isImplicitForEach })
        XCTAssertTrue(secondTargets.contains { $0.identifier == "explicit-8" && !$0.isImplicitForEach })

        reader.scrollTo(8, anchor: .top)
        XCTAssertEqual(rendered.node.scrollOffset, 400, accuracy: 0.000_001)
        reader.scrollTo("explicit-8", anchor: .top)
        XCTAssertEqual(rendered.node.scrollOffset, 420, accuracy: 0.000_001)
        reader.scrollTo(8, anchor: .top)
        XCTAssertEqual(rendered.node.scrollOffset, 400, accuracy: 0.000_001)
    }

    func testDataDrivenListTaggedRowsProjectsTupleBeforeApplyingElementSelectionTags() async throws {
        let recorder = CanonicalMetadataRecorder()
        var selected: String? = "two"
        var invalidations = 0
        let binding = Binding<String?>(get: { selected }, set: { selected = $0 })
        let list = List(["one", "two"], id: \.self, selection: binding) { element in
            recorder.elementCalls.append(element)
            return [
                AnyView(
                    TupleView(
                        (
                            canonicalMetadataLeaf(element, part: "a", recorder: recorder),
                            canonicalMetadataLeaf(element, part: "b", recorder: recorder)
                        )))
            ]
        }
        XCTAssertEqual(recorder.elementCalls, ["one", "two"])
        XCTAssertTrue(recorder.leafBodies.isEmpty)

        let rendered = makeRoot(list, onInvalidate: { invalidations += 1 })
        defer { withExtendedLifetime(rendered.runtime) {} }
        let rows = rendered.node.children.filter { $0.accessibilityTraits.contains(.isSelectable) }
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.nodeTag), ["one#0", "one#1", "two#0", "two#1"])
        XCTAssertEqual(rows.map { $0.accessibilityTraits.contains(.isSelected) }, [false, false, true, true])
        let contentNodes = try rows.map { row in
            try XCTUnwrap(allNodes(in: row).first { $0.dynamicContentIndex != nil })
        }
        XCTAssertEqual(contentNodes.map(\.dynamicContentIndex), [0, 0, 1, 1])
        XCTAssertEqual(contentNodes.map(\.text), ["one.a", "one.b", "two.a", "two.b"])
        XCTAssertEqual(
            contentNodes.map { node -> String? in
                let values = node.retainedContainerValues[retainedContainerValuesIdentifier()] as? ContainerValues
                return values?.tag(for: String.self)
            },
            ["one", "one", "two", "two"])
        let firstElementSecondLeaf = try XCTUnwrap(rows.dropFirst().first)
        let secondElementFirstLeaf = try XCTUnwrap(rows.dropFirst(2).first)
        let activateFirst = try XCTUnwrap(firstElementSecondLeaf.onActivate)
        let activateSecond = try XCTUnwrap(secondElementFirstLeaf.onActivate)
        activateFirst()
        XCTAssertEqual(selected, "one")
        activateSecond()
        XCTAssertEqual(selected, "two")
        XCTAssertEqual(invalidations, 2)
        XCTAssertEqual(recorder.elementCalls, ["one", "two"])
        XCTAssertEqual(recorder.leafBodies, ["one.a", "one.b", "two.a", "two.b"])
    }

    func testRawExplicitReturnForEachArrayKeepsFollowingMountedStateWhenOptionalDisappears() async throws {
        try assertRawArrayKeepsFollowingMountedState(route: .forEach)
    }

    func testPrebuiltRawArrayInListTaggedRowsKeepsFollowingMountedStateWhenOptionalDisappears() async throws {
        try assertRawArrayKeepsFollowingMountedState(route: .dataList)
    }

    func testRepeatedLegacyArrayPrefixesKeepFollowingMountedStateWhenFirstOptionalDisappears() async throws {
        try assertRawArrayKeepsFollowingMountedState(route: .repeatedLegacyPrefixes)
    }

    private func assertRawArrayKeepsFollowingMountedState(route: CanonicalMetadataRawArrayRoute) throws {
        let model = CanonicalMetadataStateModel()
        let capture = CanonicalMetadataStateCapture()
        var selection: String? = "element"
        let binding = Binding<String?>(get: { selection }, set: { selection = $0 })

        func currentRawArray() -> [AnyView] {
            let optional: CanonicalMetadataStateTail? =
                model.includesOptional
                ? CanonicalMetadataStateTail(name: "optional", seed: 3, capture: capture)
                : nil
            let tail = CanonicalMetadataStateTail(name: "tail", seed: 7, capture: capture)
            guard route == .repeatedLegacyPrefixes else { return [AnyView(optional), AnyView(tail)] }

            let optionalTail: CanonicalMetadataStateTail? = tail
            let first: [AnyView] = ViewBuilder.buildBlock([AnyView(optional)])
            let second: [AnyView] = ViewBuilder.buildBlock([AnyView(optionalTail)])
            guard let firstEntry = first.first, let secondEntry = second.first else {
                XCTFail("The direct legacy block must retain its raw optional entry before projection")
                return []
            }
            XCTAssertFalse(firstEntry.structuralIdentity.isEmpty)
            XCTAssertEqual(firstEntry.structuralIdentity, secondEntry.structuralIdentity)
            return [firstEntry, secondEntry]
        }

        let content = CanonicalMetadataStateRoot(model: model) {
            let previousBodies = capture.totalBodyCalls
            if route == .dataList {
                let prebuilt = currentRawArray()
                let list = List(["element"], id: \.self, selection: binding) { _ in
                    capture.elementCalls += 1
                    return prebuilt
                }
                capture.metadataBodyCounts.append((previousBodies, capture.totalBodyCalls))
                return [AnyView(list)]
            }
            let rows = ForEach(["element"], id: \.self) { _ in
                capture.elementCalls += 1
                return currentRawArray()
            }
            capture.metadataBodyCounts.append((previousBodies, capture.totalBodyCalls))
            return [AnyView(VStack(spacing: 0) { rows })]
        }
        XCTAssertEqual(capture.totalBodyCalls, 0)
        XCTAssertEqual(capture.elementCalls, 0)
        let fixture = try CanonicalMetadataStateWindow(content)
        defer { fixture.close() }
        let tail = try fixture.node("tail")
        let identity = try XCTUnwrap(tail.retainedViewIdentity)
        let tailBinding = try XCTUnwrap(capture.bindings["tail"])
        let optionalBinding = try XCTUnwrap(capture.bindings["optional"])
        XCTAssertEqual(tail.nodeTag, "element#1")
        XCTAssertEqual(tail.dynamicContentIndex, 0)
        XCTAssertEqual(tail.text, "7")

        tailBinding.wrappedValue = 41
        fixture.flush()
        XCTAssertEqual(try fixture.node("tail").text, "41")
        let optionalBodies = capture.bodyCalls["optional", default: 0]

        model.includesOptional = false
        fixture.flush()

        let retained = try fixture.node("tail")
        XCTAssertTrue(retained === tail)
        XCTAssertEqual(retained.retainedViewIdentity, identity)
        XCTAssertEqual(retained.nodeTag, "element#0")
        XCTAssertEqual(retained.dynamicContentIndex, 0)
        XCTAssertEqual(retained.text, "41")
        XCTAssertEqual(tailBinding.wrappedValue, 41)
        XCTAssertTrue(fixture.nodes("optional").isEmpty)
        XCTAssertEqual(capture.bodyCalls["optional", default: 0], optionalBodies)

        tailBinding.wrappedValue = 42
        fixture.flush()
        XCTAssertTrue(try fixture.node("tail") === tail)
        XCTAssertEqual(tail.text, "42")
        XCTAssertEqual(try XCTUnwrap(capture.bindings["tail"]).wrappedValue, 42)
        optionalBinding.wrappedValue = 99
        fixture.flush()
        XCTAssertEqual(optionalBinding.wrappedValue, 3)
        XCTAssertTrue(fixture.nodes("optional").isEmpty)
        XCTAssertGreaterThan(capture.elementCalls, 0)
        XCTAssertEqual(capture.elementCalls, capture.metadataBodyCounts.count)
        for counts in capture.metadataBodyCounts {
            XCTAssertEqual(counts.0, counts.1, "Normalizing raw arrays must not evaluate a custom body")
        }
    }

    private func assertPairRows<Data: RandomAccessCollection, ID: Hashable>(
        _ rows: ForEach<Data, ID>,
        recorder: CanonicalMetadataRecorder,
        labels: [String] = ["one.a", "one.b", "two.a", "two.b"],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recorder.elementCalls, ["one", "two"], file: file, line: line)
        XCTAssertTrue(
            recorder.leafBodies.isEmpty, "Metadata projection must not evaluate custom bodies", file: file, line: line)
        XCTAssertEqual(rows.contentViews.count, 4, file: file, line: line)
        XCTAssertEqual(rows.contentViews.map { $0.selectionTag?.base as? String }, labels, file: file, line: line)

        let rendered = makeRoot(VStack(spacing: 0) { rows })
        defer { withExtendedLifetime(rendered.runtime) {} }
        let nodes = rendered.node.children
        XCTAssertEqual(nodes.count, 4, file: file, line: line)
        XCTAssertEqual(nodes.map(\.text), labels, file: file, line: line)
        XCTAssertEqual(nodes.map(\.dynamicContentIndex), [0, 0, 1, 1], file: file, line: line)
        XCTAssertEqual(nodes.map(\.nodeTag), ["one#0", "one#1", "two#0", "two#1"], file: file, line: line)
        XCTAssertEqual(
            nodes.map { node -> String? in
                let values = node.retainedContainerValues[retainedContainerValuesIdentifier()] as? ContainerValues
                return values?.tag(for: String.self)
            }, labels, file: file, line: line)
        XCTAssertEqual(
            nodes.map { node -> String? in
                let values = node.retainedContainerValues[retainedContainerValuesIdentifier()] as? ContainerValues
                return values?.implicitSymbolTag?.base as? String
            }, ["one", "one", "two", "two"], file: file, line: line)
        XCTAssertEqual(recorder.elementCalls, ["one", "two"], file: file, line: line)
        XCTAssertEqual(recorder.leafBodies, labels, file: file, line: line)
    }

    private func makeRoot<Content: View>(
        _ view: Content,
        size: Size = Size(width: 400, height: 400),
        onInvalidate: @escaping () -> Void = {}
    ) -> (runtime: RetainedViewRuntime, node: ViewNode) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: onInvalidate)
        let node = AnyView(view).makeComponent(context: context).makeNode(runtime: runtime)
        return (runtime, node)
    }

    private func allNodes(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { allNodes(in: $0) }
    }
}

@MainActor
private final class CanonicalMetadataRecorder {
    var rootBodyCalls = 0
    var elementCalls: [String] = []
    var leafBodies: [String] = []
}

@MainActor
private struct CanonicalMetadataInheritedRows: View {
    let recorder: CanonicalMetadataRecorder

    var body: ForEach<[String], String> {
        let _ = { recorder.rootBodyCalls += 1 }()
        ForEach(["one", "two"], id: \.self) { element in
            let _ = recorder.elementCalls.append(element)
            canonicalMetadataLeaf(element, part: "a", recorder: recorder)
            canonicalMetadataLeaf(element, part: "b", recorder: recorder)
        }
    }
}

@MainActor
private struct CanonicalMetadataLeaf: View {
    let label: String
    let recorder: CanonicalMetadataRecorder

    var body: Text {
        let _ = recorder.leafBodies.append(label)
        Text(label)
    }
}

@MainActor
private func canonicalMetadataLeaf(
    _ element: String, part: String, recorder: CanonicalMetadataRecorder
) -> some View {
    let label = "\(element).\(part)"
    return CanonicalMetadataLeaf(label: label, recorder: recorder).tag(label)
}

private struct CanonicalMetadataCollidingID: Hashable, CustomStringConvertible {
    let value: Int

    var description: String { "shared" }
}

@MainActor
private final class CanonicalMetadataHost {
    let runtime: RetainedViewRuntime
    private let host: ComponentHost

    init<Content: View>(_ content: @escaping @MainActor () -> Content) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 400) },
            invalidateHandler: { [weak host] in host?.reload() })
        self.runtime = runtime
        self.host = host
        host.setComponents { [AnyView(content()).makeComponent(context: context)] }
    }

    var nodes: [ViewNode] {
        allNodes(in: runtime.root)
    }

    func reload() {
        host.reload()
    }

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one node for \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func contentRoot(file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        XCTAssertEqual(runtime.root.children.count, 1, file: file, line: line)
        return try XCTUnwrap(runtime.root.children.first, file: file, line: line)
    }

    private func allNodes(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { allNodes(in: $0) }
    }
}

private enum CanonicalMetadataRawArrayRoute: Equatable {
    case forEach
    case dataList
    case repeatedLegacyPrefixes
}

@MainActor
private final class CanonicalMetadataStateModel: ObservableObject {
    @Published var includesOptional = true
}

@MainActor
private final class CanonicalMetadataStateCapture {
    var bindings: [String: Binding<Int>] = [:]
    var bodyCalls: [String: Int] = [:]
    var totalBodyCalls = 0
    var elementCalls = 0
    var metadataBodyCounts: [(Int, Int)] = []

    func record(_ name: String, binding: Binding<Int>) {
        bindings[name] = binding
        bodyCalls[name, default: 0] += 1
        totalBodyCalls += 1
    }
}

private struct CanonicalMetadataStateRoot: View {
    @ObservedObject private var model: CanonicalMetadataStateModel
    private let content: @MainActor () -> [AnyView]

    init(model: CanonicalMetadataStateModel, content: @escaping @MainActor () -> [AnyView]) {
        self.model = model
        self.content = content
    }

    var body: [AnyView] {
        let _ = model.includesOptional
        return content()
    }
}

private struct CanonicalMetadataStateTail: View {
    @State private var value: Int
    let name: String
    let capture: CanonicalMetadataStateCapture

    init(name: String, seed: Int, capture: CanonicalMetadataStateCapture) {
        self._value = State(initialValue: seed)
        self.name = name
        self.capture = capture
    }

    var body: some View {
        let current = value
        let _ = capture.record(name, binding: $value)
        Text(String(current)).accessibilityIdentifier(name)
    }
}

@MainActor
private final class CanonicalMetadataStateWindow {
    private let host: WinSwiftUIWindowHost
    private let window: Win32Window
    private let clock: RuntimeTestClock

    init<Content: View>(_ content: Content) throws {
        let configuration = WindowGroupConfiguration(
            title: "Canonical metadata state", size: IntSize(width: 400, height: 300), clearColor: .black,
            content: [AnyView(content)])
        let clock = RuntimeTestClock()
        clock.now = 7_500
        let handle = try XCTUnwrap(NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1)))
        let surface = SurfaceDescriptor(
            windowHandle: handle, pixelSize: configuration.size, scaleFactor: 1)
        let window = Win32Window(title: configuration.title, clientSize: configuration.size)
        let host = WinSwiftUIWindowHost(
            configuration: configuration, platformWindow: window,
            renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.host = host
        self.window = window
        self.clock = clock
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        flush()
    }

    func flush() {
        for _ in 0..<2 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
        }
    }

    func close() { host.windowWillClose(window) }

    func nodes(_ identifier: String) -> [ViewNode] {
        allNodes(in: host.hostedRuntime.root).filter { $0.accessibilityIdentifier == identifier }
    }

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = nodes(identifier)
        XCTAssertEqual(matches.count, 1, "Expected one node for \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    private func allNodes(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { allNodes(in: $0) }
    }
}
