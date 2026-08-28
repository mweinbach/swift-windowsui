import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsUI
import WinSwiftUI
import XCTest

/// Windows compatibility fixtures, separate from the native-shaped builder
/// witnesses: raw arrays, Void expressions, loops, and direct array helpers are
/// deliberate extensions. Passing these tests does not qualify native SwiftUI.
@MainActor
final class CanonicalViewBuilderArrayCompatibilityTests: XCTestCase {
    func testExplicitArrayBuilderResultsKeepEmptySingleAndMultipleChildren() async {
        let empty = canonicalArrayRows {}
        let single = canonicalArrayRows { Text("single") }
        let multiple = canonicalArrayRows {
            Text("first")
            Text("second")
        }

        XCTAssertEqual(empty.count, 0)
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(multiple.count, 2)
        let rendered = CanonicalArrayRender(
            VStack {
                empty
                single
                multiple
            })
        XCTAssertEqual(rendered.texts, ["single", "first", "second"])
        XCTAssertEqual(rendered.node.children.count, 3)
    }

    func testDirectArrayHelpersRetainExplicitArrayResultsAndVisibleContent() async {
        let source = [AnyView(Text("row")), AnyView(Text("row"))]
        let expression: [AnyView] = ViewBuilder.buildExpression(source)
        let viewExpression: [AnyView] = ViewBuilder.buildExpression(Text("single"))
        let forEachExpression: [AnyView] = ViewBuilder.buildExpression(
            ForEach([1, 2], id: \.self) { Text("item \($0)") })
        let emptyBlock: [AnyView] = ViewBuilder.buildBlock()
        let oneBlock: [AnyView] = ViewBuilder.buildBlock(expression)
        let manyBlock: [AnyView] = ViewBuilder.buildBlock(expression, viewExpression)
        let present: [AnyView] = ViewBuilder.buildOptional(expression)
        let absent: [AnyView] = ViewBuilder.buildOptional(Optional<[AnyView]>.none)
        let first: [AnyView] = ViewBuilder.buildEither(first: expression)
        let second: [AnyView] = ViewBuilder.buildEither(second: viewExpression)
        let loop: [AnyView] = ViewBuilder.buildArray([viewExpression, expression])
        let available: [AnyView] = ViewBuilder.buildLimitedAvailability(expression)
        let finalized: [AnyView] = ViewBuilder.buildFinalResult(
            ViewBuilder.buildBlock(Text("final first"), Text("final second")))

        XCTAssertEqual(expression.count, 2)
        XCTAssertEqual(viewExpression.count, 1)
        XCTAssertEqual(forEachExpression.count, 2)
        XCTAssertEqual(emptyBlock.count, 0)
        XCTAssertEqual(oneBlock.count, 2)
        XCTAssertEqual(manyBlock.count, 3)
        XCTAssertEqual(present.count, 2)
        XCTAssertEqual(absent.count, 0)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(loop.count, 3)
        XCTAssertEqual(available.count, 2)
        XCTAssertEqual(finalized.count, 2)
        let rendered = CanonicalArrayRender(
            VStack {
                emptyBlock
                oneBlock
                manyBlock
                present
                absent
                first
                second
                loop
                available
                forEachExpression
                finalized
            })

        XCTAssertEqual(
            rendered.texts,
            [
                "row", "row", "row", "row", "single", "row", "row", "row", "row", "single",
                "single", "row", "row", "row", "row", "item 1", "item 2", "final first", "final second",
            ])
        XCTAssertEqual(rendered.node.children.count, 19)
    }

    func testUncontextualizedRawArrayExpressionsInferAViewAdapterAndReErase() async {
        let source = [AnyView(Text("first")), AnyView(Text("second"))]
        let direct = ViewBuilder.buildExpression(source)
        let inferred = canonicalArrayContent { source }
        let empty = ViewBuilder.buildExpression([AnyView]())

        assertCanonicalNotRawArray(direct)
        assertCanonicalNotRawArray(inferred)
        assertCanonicalNotRawArray(empty)
        let rendered = CanonicalArrayRender(
            VStack {
                empty
                direct
                inferred
                AnyView(AnyView(direct))
            })

        XCTAssertEqual(rendered.texts, ["first", "second", "first", "second", "first", "second"])
        XCTAssertEqual(rendered.node.children.count, 6)
    }

    func testVoidExpressionsSupportTypedEmptyAndExplicitLegacyArrayCalls() async {
        let typed = ViewBuilder.buildExpression(())
        let array: [AnyView] = ViewBuilder.buildExpression(())
        let counter = CanonicalArrayCounter()
        let rows = canonicalArrayRows {
            counter.increment()
            Text("array tail")
        }
        let generic = canonicalArrayContent {
            counter.increment()
            Text("typed tail")
        }

        XCTAssertEqual(ObjectIdentifier(type(of: typed)), ObjectIdentifier(EmptyView.self))
        XCTAssertTrue(array.isEmpty)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(counter.calls, 2)
        let rendered = CanonicalArrayRender(
            VStack {
                typed
                array
                rows
                generic
            })

        XCTAssertEqual(rendered.texts, ["array tail", "typed tail"])
        XCTAssertEqual(rendered.node.children.count, 2)
        XCTAssertEqual(counter.calls, 2, "Void authoring expressions must not be replayed while rendering.")
    }

    func testWindowsArrayBuilderMigrationKeepsOpaqueLoopOrderWithoutRowsForEmptyIterations() async throws {
        let typed = windowsArrayCompatibilityRows {
            for index in 0..<4 {
                if index.isMultiple(of: 2) {
                    Text("typed \(index)").frame(width: 70, height: 10)
                }
            }
            Text("following").frame(width: 70, height: 10)
        }
        let rows = windowsArrayCompatibilityRows {
            for index in 0..<4 {
                if index.isMultiple(of: 2) {
                    Text("array \(index)").frame(width: 70, height: 10)
                }
            }
        }
        let rendered = CanonicalArrayRender(
            VStack(alignment: .leading, spacing: 7) {
                typed
                rows
            })

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rendered.texts, ["typed 0", "typed 2", "following", "array 0", "array 2"])
        XCTAssertEqual(rendered.node.children.count, 5)
        for (first, second) in zip(rendered.node.children, rendered.node.children.dropFirst()) {
            let firstFrame = try XCTUnwrap(rendered.runtime.resolvedLayoutFrame(of: first))
            let secondFrame = try XCTUnwrap(rendered.runtime.resolvedLayoutFrame(of: second))
            XCTAssertEqual(secondFrame.minY - firstFrame.minY, 17, accuracy: 0.000_001)
        }
    }

    func testExplicitReturnArraysRetainTheirShapeAndRenderCurrentErasedTuples() async {
        var tuple = ViewBuilder.buildBlock(Text("old first"), Text("old second"))
        let oldErasure = AnyView(tuple)
        tuple.value = (Text("new first"), Text("new second"))
        let rows = canonicalArrayRows {
            return [oldErasure, AnyView(tuple)]
        }

        XCTAssertEqual(rows.count, 2, "An explicit return bypasses builder finalization.")
        let rendered = CanonicalArrayRender(VStack { rows })
        XCTAssertEqual(rendered.texts, ["old first", "old second", "new first", "new second"])
        XCTAssertEqual(rendered.node.children.count, 4)
    }

    func testGenericTupleReadsCurrentActualViewsBehindAnyAndBaseClassTypes() async {
        var boxed = TupleView<Any>(Text("old boxed") as Any)
        let oldBoxedCopy = boxed
        let oldBoxedErasure = AnyView(boxed)
        boxed.value = Text("new boxed") as Any
        let newBoxedErasure = AnyView(AnyView(boxed))

        var base = TupleView<CanonicalActualViewBase>(CanonicalActualViewSubclass(value: "old base"))
        let oldBaseCopy = base
        let oldBaseErasure = AnyView(base)
        base.value = CanonicalActualViewSubclass(value: "new base")
        let newBaseErasure = AnyView(AnyView(base))

        let rendered = CanonicalArrayRender(
            VStack {
                oldBoxedCopy
                oldBoxedErasure
                boxed
                newBoxedErasure
                oldBaseCopy
                oldBaseErasure
                base
                newBaseErasure
            })

        XCTAssertEqual(
            rendered.texts,
            ["old boxed", "old boxed", "new boxed", "new boxed", "old base", "old base", "new base", "new base"])
        XCTAssertEqual(rendered.node.children.count, 8)
    }

    func testUnsupportedTupleValueDoesNotInvokeCustomMirror() async {
        let recorder = CanonicalMirrorRecorder()
        let unsupported = TupleView(CanonicalUnsupportedTupleValue(recorder: recorder))
        let erased = AnyView(unsupported)
        let boxedValue: Any = CanonicalUnsupportedTupleValue(recorder: recorder)
        let baseValue: CanonicalUnsupportedTupleBase = CanonicalUnsupportedTupleSubclass(recorder: recorder)
        let boxedTuple = TupleView(boxedValue)
        let baseTuple = TupleView(baseValue)
        XCTAssertEqual(recorder.calls, 0)

        let rendered = CanonicalArrayRender(
            VStack {
                Text("before")
                unsupported
                erased
                boxedTuple
                AnyView(boxedTuple)
                baseTuple
                AnyView(baseTuple)
                Text("after")
            })

        XCTAssertEqual(recorder.calls, 0, "Tuple projection must reject CustomReflectable before inspection.")
        XCTAssertEqual(rendered.texts, ["before", "after"])
    }
}

@MainActor
private func canonicalArrayRows(@ViewBuilder _ content: () -> [AnyView]) -> [AnyView] {
    content()
}

@MainActor
private func windowsArrayCompatibilityRows(@WindowsArrayViewBuilder _ content: () -> [AnyView]) -> [AnyView] {
    content()
}

@MainActor
private func canonicalArrayContent<Content: View>(@ViewBuilder _ content: () -> Content) -> Content {
    content()
}

@MainActor
private func assertCanonicalNotRawArray<Value>(
    _ value: Value, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertNotEqual(ObjectIdentifier(Value.self), ObjectIdentifier([AnyView].self), file: file, line: line)
}

@MainActor
private struct CanonicalArrayRender {
    let runtime: RetainedViewRuntime
    let node: ViewNode

    init<V: View>(_ view: V, file: StaticString = #filePath, line: UInt = #line) {
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(of: view, size: IntSize(width: 400, height: 600))
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
private final class CanonicalArrayCounter {
    var calls = 0

    func increment() {
        calls += 1
    }
}

@MainActor
private class CanonicalActualViewBase {}

@MainActor
private final class CanonicalActualViewSubclass: CanonicalActualViewBase, View {
    let value: String

    init(value: String) {
        self.value = value
        super.init()
    }

    var body: Text { Text(value) }
}

private final class CanonicalMirrorRecorder {
    var calls = 0
}

private struct CanonicalUnsupportedTupleValue: CustomReflectable {
    let recorder: CanonicalMirrorRecorder

    var customMirror: Mirror {
        recorder.calls += 1
        return Mirror(reflecting: ("A custom mirror must not supply tuple children.", 0))
    }
}

private class CanonicalUnsupportedTupleBase {}

private final class CanonicalUnsupportedTupleSubclass: CanonicalUnsupportedTupleBase, CustomReflectable {
    let recorder: CanonicalMirrorRecorder

    init(recorder: CanonicalMirrorRecorder) {
        self.recorder = recorder
        super.init()
    }

    var customMirror: Mirror {
        recorder.calls += 1
        return Mirror(reflecting: ("A subclass mirror must not supply tuple children.", 0))
    }
}
