import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsUI
import WinSwiftUI
import XCTest

/// Windows-only array-builder fixtures. All view-authoring loops belong to an explicit
/// WindowsArrayViewBuilder scope; canonical ViewBuilder fixtures contain no loops.
/// Public imports exercise the shipped API without a test-only context initializer.
@MainActor
final class WindowsArrayViewBuilderTests: XCTestCase {
    func testOpaqueWindowsFactoryRendersItsArrayChildrenInOrder() async {
        let content = windowsOpaqueArrayFactory([2, 0, 1])
        assertWindowsArrayType(content)
        let rendered = WindowsArrayRender(VStack { content })

        XCTAssertEqual(rendered.texts, ["factory 2", "factory 0", "factory 1"])
        XCTAssertEqual(rendered.node.children.count, 3)
    }

    func testExplicitWindowsArrayBodyWitnessLaysOutLoopChildrenHorizontally() async throws {
        let view = WindowsArrayLoopBody(values: [4, 2])
        let body: [AnyView] = view.body
        XCTAssertEqual(body.count, 2)
        XCTAssertEqual(ObjectIdentifier(WindowsArrayLoopBody.Body.self), ObjectIdentifier([AnyView].self))
        let rendered = WindowsArrayRender(
            HStack(alignment: .top, spacing: 7) {
                view
            })

        XCTAssertEqual(rendered.texts, ["body 4", "body 2"])
        XCTAssertEqual(rendered.node.children.count, 2)
        let first = try XCTUnwrap(rendered.node.children.first)
        let second = try XCTUnwrap(rendered.node.children.last)
        let firstFrame = try XCTUnwrap(rendered.runtime.resolvedLayoutFrame(of: first))
        let secondFrame = try XCTUnwrap(rendered.runtime.resolvedLayoutFrame(of: second))
        XCTAssertEqual(firstFrame.size, Size(width: 70, height: 10))
        XCTAssertEqual(secondFrame.size, Size(width: 70, height: 10))
        XCTAssertEqual(secondFrame.minX - firstFrame.minX, 77, accuracy: 0.000_001)
        XCTAssertEqual(secondFrame.minY, firstFrame.minY, accuracy: 0.000_001)
    }

    func testOpaqueWindowsModifierLoopBuildsOnceAndPreservesItsContent() async {
        let counter = WindowsArrayBuildCounter()
        let modified = Text("content").modifier(WindowsArrayLoopModifier(values: [3, 1], counter: counter))
        let stack = VStack { modified }

        XCTAssertEqual(ObjectIdentifier(WindowsArrayLoopModifier.Body.self), ObjectIdentifier([AnyView].self))
        XCTAssertEqual(counter.calls, 0, "Creating a modifier and its parent must not evaluate the modifier body.")
        let rendered = WindowsArrayRender(stack)
        XCTAssertEqual(rendered.texts, ["content", "modifier 3", "modifier 1"])
        XCTAssertEqual(rendered.node.children.count, 3)
        XCTAssertEqual(counter.calls, 1)

        _ = rendered.runtime.renderScene()
        XCTAssertEqual(counter.calls, 1, "Painting the retained tree must not rerun the authoring loop.")
    }

    func testEmptyOptionalAndEitherBodiesDoNotAddEmptyChildren() async {
        let empty: [AnyView] = windowsArrayRows {}
        let opaqueEmpty = windowsOpaqueArrayEmpty()
        let present = windowsOpaqueArrayBranches(showsOptional: true, usesFirst: true)
        let absent = windowsOpaqueArrayBranches(showsOptional: false, usesFirst: false)

        XCTAssertTrue(empty.isEmpty)
        assertWindowsArrayType(opaqueEmpty)
        assertWindowsArrayType(present)
        assertWindowsArrayType(absent)
        let rendered = WindowsArrayRender(
            VStack {
                empty
                opaqueEmpty
                present
                absent
            })

        XCTAssertEqual(rendered.texts, ["optional", "first", "second"])
        XCTAssertEqual(rendered.node.children.count, 3)
    }

    func testNestedWindowsIterationsKeepOrderAndSkipEmptyIterationBodies() async throws {
        let rows = windowsOpaqueNestedArrays()
        assertWindowsArrayType(rows)
        let rendered = WindowsArrayRender(
            VStack(alignment: .leading, spacing: 7) {
                rows
            })

        XCTAssertEqual(rendered.texts, ["0.0", "0.1", "2.0", "2.1", "following"])
        XCTAssertEqual(rendered.node.children.count, 5)
        for (first, second) in zip(rendered.node.children, rendered.node.children.dropFirst()) {
            let firstFrame = try XCTUnwrap(rendered.runtime.resolvedLayoutFrame(of: first))
            let secondFrame = try XCTUnwrap(rendered.runtime.resolvedLayoutFrame(of: second))
            XCTAssertEqual(secondFrame.minY - firstFrame.minY, 17, accuracy: 0.000_001)
        }
    }

    func testRawArraysVoidAndAvailabilityKeepVisibleContentWithoutReplayingSideEffects() async {
        let counter = WindowsArrayBuildCounter()
        let source = [AnyView(Text("array first")), AnyView(Text("array second"))]
        let rows: [AnyView] = windowsArrayRows {
            counter.increment()
            source
            [AnyView]()
            if #available(macOS 26.0, *) {
                Text("available")
            } else {
                Text("unavailable")
            }
            counter.increment()
        }

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(counter.calls, 2)
        let rendered = WindowsArrayRender(VStack { rows })
        XCTAssertEqual(rendered.texts, ["array first", "array second", "available"])
        XCTAssertEqual(rendered.node.children.count, 3)
        XCTAssertEqual(counter.calls, 2)
    }

    func testPublicDirectHelpersReturnFixedArraysAndPreserveVisibleOrder() async {
        let expression: [AnyView] = WindowsArrayViewBuilder.buildExpression(Text("direct"))
        let raw: [AnyView] = WindowsArrayViewBuilder.buildExpression([AnyView(Text("raw"))])
        let void: [AnyView] = WindowsArrayViewBuilder.buildExpression(())
        let empty: [AnyView] = WindowsArrayViewBuilder.buildBlock()
        let block: [AnyView] = WindowsArrayViewBuilder.buildBlock(expression, raw)
        let present: [AnyView] = WindowsArrayViewBuilder.buildOptional(expression)
        let absent: [AnyView] = WindowsArrayViewBuilder.buildOptional(Optional<[AnyView]>.none)
        let first: [AnyView] = WindowsArrayViewBuilder.buildEither(first: expression)
        let second: [AnyView] = WindowsArrayViewBuilder.buildEither(second: raw)
        let loop: [AnyView] = WindowsArrayViewBuilder.buildArray([expression, [], raw])
        let available: [AnyView] = WindowsArrayViewBuilder.buildLimitedAvailability(raw)
        let inferredEmpty = WindowsArrayViewBuilder.buildBlock()
        let inferredExpression = WindowsArrayViewBuilder.buildExpression(Text("inferred"))

        assertWindowsArrayType(inferredEmpty)
        assertWindowsArrayType(inferredExpression)
        XCTAssertEqual(expression.count, 1)
        XCTAssertEqual(raw.count, 1)
        XCTAssertTrue(void.isEmpty)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(block.count, 2)
        XCTAssertEqual(present.count, 1)
        XCTAssertTrue(absent.isEmpty)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(loop.count, 2)
        XCTAssertEqual(available.count, 1)
        let rendered = WindowsArrayRender(
            VStack {
                empty
                block
                present
                absent
                first
                second
                loop
                available
                void
            })

        XCTAssertEqual(rendered.texts, ["direct", "raw", "direct", "direct", "raw", "direct", "raw", "raw"])
        XCTAssertEqual(rendered.node.children.count, 8)
    }

    func testForEachExpressionExposesRowsBeforeTheWindowsArrayBlock() async {
        let repeated = ForEach([8, 3], id: \.self) { value in
            Text("foreach \(value)")
        }
        let direct: [AnyView] = WindowsArrayViewBuilder.buildExpression(repeated)
        let rows: [AnyView] = windowsArrayRows {
            Text("before")
            repeated
            Text("after")
        }

        XCTAssertEqual(direct.count, 2)
        XCTAssertEqual(rows.count, 4, "The specialized expression must expose logical rows, not one ForEach box.")
        let rendered = WindowsArrayRender(HStack { rows })
        XCTAssertEqual(rendered.texts, ["before", "foreach 8", "foreach 3", "after"])
        XCTAssertEqual(rendered.node.children.count, 4)
    }

    func testWindowsArraysComposeWithUnchangedCanonicalConcreteAndGenericConsumers() async {
        let rows: [AnyView] = windowsArrayRows {
            for value in 0..<2 {
                Text("legacy \(value)")
            }
        }
        let concrete = WindowsArrayConcreteConsumer(rows: rows)
        let concreteBody: VStack = concrete.body
        let canonicalText: Text = windowsCanonicalText()
        let typedSingle: WindowsArrayTypedContent<Text> = WindowsArrayTypedContent { canonicalText }
        let singleContent: Text = typedSingle.content
        let typedMultiple = WindowsArrayTypedContent {
            rows
            singleContent
        }

        XCTAssertEqual(ObjectIdentifier(type(of: concreteBody)), ObjectIdentifier(VStack.self))
        XCTAssertEqual(ObjectIdentifier(type(of: singleContent)), ObjectIdentifier(Text.self))
        XCTAssertNotEqual(ObjectIdentifier(type(of: typedMultiple.content)), ObjectIdentifier([AnyView].self))
        let rendered = WindowsArrayRender(
            VStack {
                concrete
                typedSingle
                typedMultiple
            })

        XCTAssertEqual(
            rendered.texts,
            ["legacy 0", "legacy 1", "concrete tail", "canonical", "legacy 0", "legacy 1", "canonical"])
        XCTAssertEqual(rendered.node.children.count, 5, "The concrete VStack retains its own layout boundary.")
        XCTAssertEqual(rendered.node.children.first?.children.count, 3)
    }
}

@MainActor
private func assertWindowsArrayType<Value>(
    _ value: Value, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(ObjectIdentifier(Value.self), ObjectIdentifier([AnyView].self), file: file, line: line)
}

@MainActor
private func windowsArrayRows(@WindowsArrayViewBuilder _ content: () -> [AnyView]) -> [AnyView] {
    content()
}

@MainActor
@WindowsArrayViewBuilder
private func windowsOpaqueArrayFactory(_ values: [Int]) -> some View {
    for value in values {
        Text("factory \(value)").frame(width: 70, height: 10)
    }
}

@MainActor
@WindowsArrayViewBuilder
private func windowsOpaqueArrayEmpty() -> some View {}

@MainActor
@WindowsArrayViewBuilder
private func windowsOpaqueArrayBranches(showsOptional: Bool, usesFirst: Bool) -> some View {
    if showsOptional {
        Text("optional")
    }
    if usesFirst {
        Text("first")
    } else {
        Text("second")
    }
}

@MainActor
@WindowsArrayViewBuilder
private func windowsOpaqueNestedArrays() -> some View {
    for outer in 0..<3 {
        for inner in 0..<2 {
            if outer != 1 {
                Text("\(outer).\(inner)").frame(width: 70, height: 10)
            }
        }
    }
    Text("following").frame(width: 70, height: 10)
}

@MainActor
@ViewBuilder
private func windowsCanonicalText() -> Text {
    Text("canonical")
}

@MainActor
private struct WindowsArrayLoopBody: View {
    let values: [Int]

    @WindowsArrayViewBuilder
    var body: [AnyView] {
        for value in values {
            Text("body \(value)").frame(width: 70, height: 10)
        }
    }
}

@MainActor
private struct WindowsArrayLoopModifier: ViewModifier {
    let values: [Int]
    let counter: WindowsArrayBuildCounter

    @WindowsArrayViewBuilder
    func body(content: Content) -> some View {
        counter.increment()
        content
        for value in values {
            Text("modifier \(value)").frame(width: 70, height: 10)
        }
    }
}

@MainActor
private struct WindowsArrayConcreteConsumer: View {
    let rows: [AnyView]

    var body: VStack {
        VStack {
            rows
            Text("concrete tail")
        }
    }
}

@MainActor
private struct WindowsArrayTypedContent<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: Content { content }
}

@MainActor
private final class WindowsArrayBuildCounter {
    var calls = 0

    func increment() {
        calls += 1
    }
}

@MainActor
private struct WindowsArrayRender {
    let runtime: RetainedViewRuntime
    let node: ViewNode

    init<V: View>(_ view: V, file: StaticString = #filePath, line: UInt = #line) {
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(of: view, size: IntSize(width: 500, height: 400))
        XCTAssertEqual(snapshot.runtime.root.children.count, 1, file: file, line: line)
        XCTAssertTrue(snapshot.scene.validate().isEmpty, file: file, line: line)
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
