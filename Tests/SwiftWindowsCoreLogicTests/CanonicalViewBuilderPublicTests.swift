import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsUI
import WinSwiftUI
import XCTest

/// These fixtures import only public symbols. The body declarations deliberately
/// omit @ViewBuilder: they must inherit it from View, including concrete witnesses.
/// They exercise retained output, not a native-platform compatibility qualification.
@MainActor
final class CanonicalViewBuilderPublicTests: XCTestCase {
    func testConcreteAndOpaqueSingleBodiesPreserveTextAndRender() async {
        let concrete = CanonicalConcreteTextBody()
        let text: Text = concrete.body
        assertCanonicalStaticType(text, Text.self)
        XCTAssertEqual(ObjectIdentifier(CanonicalConcreteTextBody.Body.self), ObjectIdentifier(Text.self))

        let rendered = CanonicalPublicRender(
            VStack {
                concrete
                CanonicalOpaqueTextBody()
            })

        XCTAssertEqual(rendered.texts, ["concrete", "opaque"])
        XCTAssertEqual(rendered.node.children.count, 2)
    }

    func testInheritedMultiExpressionBodyUsesVerticalStackSpacing() async throws {
        let rendered = CanonicalPublicRender(
            VStack(alignment: .leading, spacing: 7) {
                CanonicalPairBody()
            })
        let first = try XCTUnwrap(rendered.node.children.first)
        let second = try XCTUnwrap(rendered.node.children.last)
        let firstFrame = try XCTUnwrap(rendered.runtime.resolvedLayoutFrame(of: first))
        let secondFrame = try XCTUnwrap(rendered.runtime.resolvedLayoutFrame(of: second))

        XCTAssertEqual(rendered.node.children.count, 2)
        XCTAssertEqual(first.accessibilityIdentifier, "canonical.first")
        XCTAssertEqual(second.accessibilityIdentifier, "canonical.second")
        XCTAssertEqual(firstFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(secondFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(secondFrame.minY - firstFrame.minY, 17, accuracy: 0.000_001)
        XCTAssertEqual(secondFrame.minX, firstFrame.minX, accuracy: 0.000_001)
    }

    func testInheritedMultiExpressionBodyUsesHorizontalStackSpacing() async throws {
        let rendered = CanonicalPublicRender(
            HStack(alignment: .top, spacing: 7) {
                CanonicalPairBody()
            })
        let first = try XCTUnwrap(rendered.node.children.first)
        let second = try XCTUnwrap(rendered.node.children.last)
        let firstFrame = try XCTUnwrap(rendered.runtime.resolvedLayoutFrame(of: first))
        let secondFrame = try XCTUnwrap(rendered.runtime.resolvedLayoutFrame(of: second))

        XCTAssertEqual(rendered.node.children.count, 2)
        XCTAssertEqual(first.accessibilityIdentifier, "canonical.first")
        XCTAssertEqual(second.accessibilityIdentifier, "canonical.second")
        XCTAssertEqual(firstFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(secondFrame.size, Size(width: 10, height: 10))
        XCTAssertEqual(secondFrame.minX - firstFrame.minX, 17, accuracy: 0.000_001)
        XCTAssertEqual(secondFrame.minY, firstFrame.minY, accuracy: 0.000_001)
    }

    func testInheritedConditionalOptionalAndSwitchBodiesRenderActiveBranches() async {
        let first = CanonicalPublicRender(
            VStack {
                CanonicalControlFlowBody(usesFirst: true, showsOptional: true, selection: 0)
                Text("following")
            })
        let second = CanonicalPublicRender(
            VStack {
                CanonicalControlFlowBody(usesFirst: false, showsOptional: false, selection: 1)
                Text("following")
            })
        let fallback = CanonicalPublicRender(
            VStack {
                CanonicalControlFlowBody(usesFirst: true, showsOptional: false, selection: 9)
            })

        XCTAssertEqual(first.texts, ["first", "optional", "zero", "following"])
        XCTAssertEqual(first.node.children.count, 4)
        XCTAssertEqual(second.texts, ["second", "one", "following"])
        XCTAssertEqual(second.node.children.count, 3)
        XCTAssertEqual(fallback.texts, ["first", "other"])
        XCTAssertEqual(fallback.node.children.count, 2)
    }

    func testInheritedForEachBodyRemainsTypedAndRendersRowsInOrder() async {
        let view = CanonicalForEachBody(values: [3, 1, 2])
        assertCanonicalStaticType(view.body, ForEach<[Int], Int>.self)
        let rendered = CanonicalPublicRender(
            VStack {
                view
                Text("following")
            })

        XCTAssertEqual(rendered.texts, ["row 3", "row 1", "row 2", "following"])
        XCTAssertEqual(rendered.node.children.count, 4)
    }

    func testExplicitReturnAndOrdinaryClosureRemainUntransformed() async {
        let returned: Text = CanonicalExplicitReturnBody().body
        let ordinary: () -> Text = { Text("ordinary") }
        let rendered = CanonicalPublicRender(
            VStack {
                returned
                ordinary()
                CanonicalExplicitStackBody()
            })

        XCTAssertEqual(rendered.texts, ["returned", "ordinary", "nested first", "nested second"])
        XCTAssertEqual(rendered.node.children.count, 3, "An explicit stack remains one layout child.")
        XCTAssertEqual(rendered.node.children.last?.children.count, 2)
    }

    func testImplicitNeverAndDefaultShapeWitnessesRemainUsable() async {
        requireCanonicalNeverBody(CanonicalNeverPrimitive.self)
        requireCanonicalNeverBody(CanonicalDefaultShape.self)
        requireCanonicalNeverBody(Never.self)
        let rendered = CanonicalPublicRender(
            VStack {
                CanonicalNeverPrimitive()
                CanonicalDefaultShape()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .accessibilityIdentifier("default.shape")
            })

        XCTAssertEqual(rendered.texts, ["primitive"])
        XCTAssertEqual(rendered.node.children.count, 2)
        XCTAssertEqual(rendered.node.children.last?.accessibilityIdentifier, "default.shape")
        let shapeFrame = rendered.node.children.last.flatMap { rendered.runtime.resolvedLayoutFrame(of: $0) }
        XCTAssertEqual(shapeFrame?.size, Size(width: 10, height: 10))
    }

    func testGenericStoredBuilderPreservesTypedContentAndRunsOnce() async {
        let counter = CanonicalBuilderCounter(value: "stored")
        let stored = CanonicalStoredContent {
            counter.makeText()
            Text("tail")
        }

        assertCanonicalStaticType(stored.content, TupleView<(Text, Text)>.self)
        XCTAssertEqual(counter.calls, 1)
        let first = CanonicalPublicRender(VStack { stored })
        let second = CanonicalPublicRender(HStack { stored })

        XCTAssertEqual(first.texts, ["stored", "tail"])
        XCTAssertEqual(second.texts, ["stored", "tail"])
        XCTAssertEqual(first.node.children.count, 2)
        XCTAssertEqual(second.node.children.count, 2)
        XCTAssertEqual(counter.calls, 1, "Rendering stored Content must not rerun its authoring closure.")
    }

    func testGenericDeferredBuilderRunsOnlyWhenItsBodyIsBuilt() async {
        let counter = CanonicalBuilderCounter(value: "first")
        let deferred = CanonicalDeferredContent {
            counter.makeText()
            Text("tail")
        }
        let erased = AnyView(AnyView(deferred))
        let firstStack = VStack { erased }

        XCTAssertEqual(counter.calls, 0, "Erasure and stack authoring must not evaluate a deferred body.")
        let first = CanonicalPublicRender(firstStack)
        XCTAssertEqual(first.texts, ["first", "tail"])
        XCTAssertEqual(first.node.children.count, 2)
        XCTAssertEqual(counter.calls, 1)

        counter.value = "second"
        let second = CanonicalPublicRender(HStack { erased })
        XCTAssertEqual(second.texts, ["second", "tail"])
        XCTAssertEqual(second.node.children.count, 2)
        XCTAssertEqual(counter.calls, 2)
    }

    func testPublicBuilderPrefersEmptySingleAndFlatPackTypes() async {
        let expression = ViewBuilder.buildExpression(Text("expression"))
        let final = ViewBuilder.buildFinalResult(expression)
        let empty = ViewBuilder.buildBlock()
        let single = ViewBuilder.buildBlock(Text("single"))
        let flat = ViewBuilder.buildBlock(Text("first"), Color.red, Text("last"))
        let inheritedEmpty = CanonicalEmptyBody()
        let inferredEmpty = canonicalPublicContent {}
        let inferredSingle = canonicalPublicContent { Text("inferred") }
        let inferredFlat = canonicalPublicContent {
            Text("one")
            Color.blue
            Text("two")
        }

        assertCanonicalStaticType(expression, Text.self)
        assertCanonicalStaticType(final, Text.self)
        assertCanonicalStaticType(empty, EmptyView.self)
        assertCanonicalStaticType(single, Text.self)
        assertCanonicalStaticType(flat, TupleView<(Text, Color, Text)>.self)
        assertCanonicalStaticType(inheritedEmpty.body, EmptyView.self)
        assertCanonicalStaticType(inferredEmpty, EmptyView.self)
        assertCanonicalStaticType(inferredSingle, Text.self)
        assertCanonicalStaticType(inferredFlat, TupleView<(Text, Color, Text)>.self)
        let values: (Text, Color, Text) = flat.value
        assertCanonicalStaticType(values.1, Color.self)

        let rendered = CanonicalPublicRender(
            VStack {
                empty
                inheritedEmpty
                inferredEmpty
                single
                flat
            })
        XCTAssertEqual(rendered.texts, ["single", "first", "last"])
        XCTAssertEqual(rendered.node.children.count, 4)
    }

    func testTypedOptionalEitherAndAvailabilityHelpersRenderThroughErasure() async {
        let present = ViewBuilder.buildIf(Optional(Text("if")))
        let optional = ViewBuilder.buildOptional(Optional(Text("optional")))
        let absent = ViewBuilder.buildIf(Optional<Text>.none)
        let first: _ConditionalContent<Text, Color> = ViewBuilder.buildEither(first: Text("either"))
        let second: _ConditionalContent<Text, Color> = ViewBuilder.buildEither(second: Color.blue)
        let available = ViewBuilder.buildLimitedAvailability(
            ViewBuilder.buildBlock(Text("available first"), Text("available second")))

        assertCanonicalStaticType(present, Text?.self)
        assertCanonicalStaticType(optional, Text?.self)
        assertCanonicalStaticType(absent, Text?.self)
        assertCanonicalStaticType(available, AnyView.self)
        let rendered = CanonicalPublicRender(
            VStack {
                present
                optional
                absent
                first
                second
                AnyView(AnyView(available))
                CanonicalAvailabilityBody()
            })

        XCTAssertEqual(
            rendered.texts,
            ["if", "optional", "either", "available first", "available second", "syntax first", "syntax second"])
        XCTAssertEqual(rendered.node.children.count, 8)
    }

    func testWholeTupleValueMutationPreservesEarlierCopiesAndErasures() async {
        var tuple = ViewBuilder.buildBlock(Text("old first"), Text("old second"))
        let oldCopy = tuple
        let oldErasure = AnyView(tuple)
        tuple.value = (Text("new first"), Text("new second"))
        let newErasure = AnyView(tuple)
        let rendered = CanonicalPublicRender(
            VStack {
                oldCopy
                oldErasure
                tuple
                newErasure
            })

        XCTAssertEqual(
            rendered.texts,
            [
                "old first", "old second", "old first", "old second",
                "new first", "new second", "new first", "new second",
            ])
        XCTAssertEqual(rendered.node.children.count, 8)
    }

    func testNestedTupleMutationReadsCurrentFieldsAndKeepsNestedPublicValueType() async {
        var nested = TupleView((TupleView((Text("first"), Text("old nested"))), Text("old tail")))
        let oldCopy = nested
        let oldErasure = AnyView(nested)
        nested.value.0.value.1 = Text("new nested")
        nested.value.1 = Text("new tail")

        assertCanonicalStaticType(nested, TupleView<(TupleView<(Text, Text)>, Text)>.self)
        let rendered = CanonicalPublicRender(
            HStack {
                nested
                oldCopy
                oldErasure
            })

        XCTAssertEqual(
            rendered.texts,
            [
                "first", "new nested", "new tail", "first", "old nested", "old tail",
                "first", "old nested", "old tail",
            ])
        XCTAssertEqual(rendered.node.children.count, 9)
    }

    func testGenericTupleInitializerReadsCurrentTupleAndSingleViewValues() async {
        var tuple = canonicalGenericTuple((Text("old"), Text("tail")))
        var single = canonicalGenericTuple(Text("old single"))
        tuple.value.0 = Text("current")
        single.value = Text("current single")
        let rendered = CanonicalPublicRender(
            VStack {
                tuple
                single
            })

        XCTAssertEqual(rendered.texts, ["current", "tail", "current single"])
        XCTAssertEqual(rendered.node.children.count, 3)
    }
}

@MainActor
private func assertCanonicalStaticType<Value>(
    _ value: Value, _ expected: Any.Type, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(ObjectIdentifier(Value.self), ObjectIdentifier(expected), file: file, line: line)
}

@MainActor
private func requireCanonicalNeverBody<V: View>(_ type: V.Type) where V.Body == Never {}

@MainActor
private func canonicalPublicContent<Content: View>(@ViewBuilder _ content: () -> Content) -> Content {
    content()
}

@MainActor
private func canonicalGenericTuple<Value>(_ value: Value) -> TupleView<Value> {
    TupleView(value)
}

@MainActor
private struct CanonicalPublicRender {
    let runtime: RetainedViewRuntime
    let node: ViewNode

    init<V: View>(_ view: V, file: StaticString = #filePath, line: UInt = #line) {
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(of: view, size: IntSize(width: 400, height: 300))
        XCTAssertEqual(snapshot.runtime.root.children.count, 1, file: file, line: line)
        XCTAssertTrue(
            snapshot.scene.validate().isEmpty, "The constructed view must produce a valid scene.", file: file,
            line: line)
        self.runtime = snapshot.runtime
        self.node = snapshot.runtime.root.children.first ?? snapshot.runtime.root
    }

    var texts: [String] {
        func collect(_ node: ViewNode) -> [String] {
            (node.text.map { [$0] } ?? []) + node.children.flatMap(collect)
        }
        return collect(node)
    }
}

@MainActor
private struct CanonicalConcreteTextBody: View {
    var body: Text { Text("concrete") }
}

@MainActor
private struct CanonicalOpaqueTextBody: View {
    var body: some View { Text("opaque") }
}

@MainActor
private struct CanonicalEmptyBody: View {
    var body: some View {}
}

@MainActor
private struct CanonicalPairBody: View {
    var body: some View {
        Color.red.frame(width: 10, height: 10).accessibilityIdentifier("canonical.first")
        Color.blue.frame(width: 10, height: 10).accessibilityIdentifier("canonical.second")
    }
}

@MainActor
private struct CanonicalControlFlowBody: View {
    let usesFirst: Bool
    let showsOptional: Bool
    let selection: Int

    var body: some View {
        if usesFirst {
            Text("first")
        } else {
            Text("second")
        }
        if showsOptional {
            Text("optional")
        }
        switch selection {
        case 0: Text("zero")
        case 1: Text("one")
        default: Text("other")
        }
    }
}

@MainActor
private struct CanonicalForEachBody: View {
    let values: [Int]

    var body: some View {
        ForEach(values, id: \.self) { value in
            Text("row \(value)")
        }
    }
}

@MainActor
private struct CanonicalExplicitReturnBody: View {
    var body: Text { return Text("returned") }
}

@MainActor
private struct CanonicalExplicitStackBody: View {
    var body: some View {
        return VStack {
            Text("nested first")
            Text("nested second")
        }
    }
}

@MainActor
private struct CanonicalNeverPrimitive: View {
    var body: Never { fatalError("A primitive body must never be evaluated.") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            let node = ViewNode()
            node.text = "primitive"
            node.preferredSize = Size(width: 70, height: 20)
            return node
        }
    }
}

@MainActor
private struct CanonicalDefaultShape: Shape {
    func path(in rect: Rect) -> Path {
        Rectangle().path(in: rect)
    }
}

@MainActor
private final class CanonicalBuilderCounter {
    var value: String
    var calls = 0

    init(value: String) {
        self.value = value
    }

    func makeText() -> Text {
        calls += 1
        return Text(value)
    }
}

@MainActor
private struct CanonicalStoredContent<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: Content { content }
}

@MainActor
private struct CanonicalDeferredContent<Content: View>: View {
    let content: @MainActor () -> Content

    init(@ViewBuilder content: @escaping @MainActor () -> Content) {
        self.content = content
    }

    var body: Content { content() }
}

@MainActor
private struct CanonicalAvailabilityBody: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Text("syntax first")
            Text("syntax second")
        } else {
            Text("unavailable")
        }
    }
}
