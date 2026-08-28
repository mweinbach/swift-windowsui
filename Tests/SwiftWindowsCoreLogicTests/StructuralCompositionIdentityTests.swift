import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

@MainActor
final class StructuralCompositionIdentityTests: XCTestCase {
    func testIdentityWrapperKeepsLeafSparseAndRestoresCapturedContext() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let captured = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}).withEnvironmentValue(
            \.displayScale, 2
        )
        .withViewIdentityPrefix([.slot(4)])
        let ambient = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}).withEnvironmentValue(
            \.displayScale, 3)
        var calls = 0
        let source = Component { _ in
            calls += 1
            XCTAssertEqual(ViewBuildContextScope.current?.displayScale, 2)
            return ViewNode()
        }
        let component = preservingViewIdentity(of: source, context: captured)
        XCTAssertFalse(component.hasStructuralChildren)
        XCTAssertEqual(calls, 0)
        var nodes: [ViewNode] = []

        ViewBuildContextScope.withCurrent(ambient) {
            component.appendChildNodes(runtime: runtime, to: &nodes)
            XCTAssertEqual(ViewBuildContextScope.current?.displayScale, 3)
        }

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.retainedViewIdentity, captured.retainedViewIdentity)
    }

    func testIdentityWrapperForwardsOnlyTheSelectedPathAndPreservesChildIdentities() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let captured = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}).withEnvironmentValue(
            \.displayScale, 2
        )
        .withViewIdentityPrefix([.slot(4)])
        let ambient = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}).withEnvironmentValue(
            \.displayScale, 3)
        let prefix = ViewNode()
        let undecorated = ViewNode()
        let specific = ViewNode()
        let specificIdentity = captured.retainedViewIdentity.appending(.slot(8))
        specific.retainedViewIdentity = specificIdentity
        var fallbackCalls = 0
        var appendCalls = 0
        let source = Component(
            makeViewNode: { _ in
                fallbackCalls += 1
                XCTAssertEqual(ViewBuildContextScope.current?.displayScale, 2)
                return ViewNode()
            },
            appendStructuralChildren: { _, nodes in
                appendCalls += 1
                XCTAssertEqual(ViewBuildContextScope.current?.displayScale, 2)
                nodes.append(contentsOf: [undecorated, specific])
            }
        )
        let component = preservingViewIdentity(of: source, context: captured)
        XCTAssertTrue(component.hasStructuralChildren)
        var nodes = [prefix]

        ViewBuildContextScope.withCurrent(ambient) {
            component.appendChildNodes(runtime: runtime, to: &nodes)
            XCTAssertEqual(ViewBuildContextScope.current?.displayScale, 3)
        }

        XCTAssertEqual(fallbackCalls, 0)
        XCTAssertEqual(appendCalls, 1)
        XCTAssertEqual(nodes.count, 3)
        XCTAssertTrue(nodes.first === prefix)
        XCTAssertNil(prefix.retainedViewIdentity)
        XCTAssertEqual(
            undecorated.retainedViewIdentity,
            captured.retainedViewIdentity.appending(.role(.content)).appending(.slot(0)))
        XCTAssertEqual(specific.retainedViewIdentity, specificIdentity)

        let fallback = component.makeNode(runtime: runtime)
        XCTAssertEqual(fallbackCalls, 1)
        XCTAssertEqual(appendCalls, 1)
        XCTAssertEqual(fallback.retainedViewIdentity, captured.retainedViewIdentity)
    }

    func testIdentityWrapperKeepsAnEmptyStructuralResultEmpty() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let prefix = ViewNode()
        let component = preservingViewIdentity(
            of: EmptyView().makeComponent(
                context: ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {})),
            context: ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}).withViewIdentityPrefix([
                .slot(2)
            ]))
        var nodes = [prefix]
        XCTAssertTrue(component.hasStructuralChildren)

        component.appendChildNodes(runtime: runtime, to: &nodes)

        XCTAssertEqual(nodes.count, 1)
        XCTAssertTrue(nodes.first === prefix)
        XCTAssertNil(prefix.retainedViewIdentity)
        XCTAssertNotNil(component.makeNode(runtime: runtime).retainedViewIdentity)
    }

    func testIdentityWrapperKeepsAKeyedProducerAsOneNode() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let recorder = StructuralCompositionRecorder()
        let context = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}).withViewIdentityPrefix([
            .slot(5)
        ])
        let source = StructuralCompositionProbe(recorder: recorder).makeComponent(context: context).keyed("owner")
        let component = preservingViewIdentity(of: source, context: context)
        var nodes: [ViewNode] = []
        XCTAssertFalse(component.hasStructuralChildren)

        component.appendChildNodes(runtime: runtime, to: &nodes)

        XCTAssertEqual(recorder.componentCalls, 1)
        XCTAssertEqual(recorder.fallbackCalls, 1)
        XCTAssertEqual(recorder.appendCalls, 0)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.nodeTag, "owner")
        XCTAssertEqual(nodes.first?.retainedViewIdentity, context.retainedViewIdentity)
    }

    func testSingleStructuralCompositionDispatchesTheCustomComponentOnlyOnce() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let recorder = StructuralCompositionRecorder()
        let component = composeStructuralComponent(
            from: [AnyView(StructuralCompositionProbe(recorder: recorder))],
            context: ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}))
        XCTAssertEqual(recorder.componentCalls, 1, "Preserve the existing single-child construction boundary.")
        XCTAssertEqual(recorder.fallbackCalls, 0)
        XCTAssertEqual(recorder.appendCalls, 0)
        var nodes: [ViewNode] = []

        component.appendChildNodes(runtime: runtime, to: &nodes)

        XCTAssertEqual(recorder.componentCalls, 1)
        XCTAssertEqual(recorder.fallbackCalls, 0)
        XCTAssertEqual(recorder.appendCalls, 1)
        XCTAssertEqual(nodes.map(\.text), ["first", "second"])
    }

    func testMultipleStructuralChildrenDispatchOnceWithoutBuildingFallbacks() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let first = StructuralCompositionRecorder()
        let second = StructuralCompositionRecorder()
        let component = composeStructuralComponent(
            from: [
                AnyView(StructuralCompositionProbe(recorder: first)),
                AnyView(StructuralCompositionProbe(recorder: second)),
            ], context: ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}))
        XCTAssertEqual(first.componentCalls, 0)
        XCTAssertEqual(second.componentCalls, 0)
        var nodes: [ViewNode] = []

        component.appendChildNodes(runtime: runtime, to: &nodes)

        XCTAssertEqual(nodes.map(\.text), ["first", "second", "first", "second"])
        for recorder in [first, second] {
            XCTAssertEqual(recorder.componentCalls, 1)
            XCTAssertEqual(recorder.fallbackCalls, 0)
            XCTAssertEqual(recorder.appendCalls, 1)
        }
        XCTAssertNotEqual(nodes.first?.retainedViewIdentity, nodes.last?.retainedViewIdentity)
    }

    func testOpaqueSingleCompositionDoesNotLeakTheChildCapability() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let recorder = StructuralCompositionRecorder()
        let component = composeComponent(
            from: [AnyView(StructuralCompositionProbe(recorder: recorder))],
            context: ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}))
        XCTAssertFalse(component.hasStructuralChildren)
        XCTAssertEqual(recorder.componentCalls, 1)
        var nodes: [ViewNode] = []

        component.appendChildNodes(runtime: runtime, to: &nodes)

        XCTAssertEqual(recorder.componentCalls, 1)
        XCTAssertEqual(recorder.fallbackCalls, 1)
        XCTAssertEqual(recorder.appendCalls, 0)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.children.map(\.text), ["first", "second"])
    }

    func testDirectCompositionFallbackKeepsTheExistingAggregateShape() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let first = StructuralCompositionRecorder()
        let second = StructuralCompositionRecorder()
        let component = composeStructuralComponent(
            from: [
                AnyView(StructuralCompositionProbe(recorder: first)),
                AnyView(StructuralCompositionProbe(recorder: second)),
            ], context: ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}))

        let node = component.makeNode(runtime: runtime)

        XCTAssertEqual(node.children.count, 2)
        for child in node.children {
            XCTAssertEqual(child.children.map(\.text), ["first", "second"])
        }
        for recorder in [first, second] {
            XCTAssertEqual(recorder.componentCalls, 1)
            XCTAssertEqual(recorder.fallbackCalls, 1)
            XCTAssertEqual(recorder.appendCalls, 0)
        }
    }

    func testRawTaggedChildrenRetainTheirNodesAcrossReorderingWithinOwner() async throws {
        let parent = ViewNode()
        let runtime = RetainedViewRuntime(root: parent)
        let context = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}).withViewIdentityPrefix([
            .slot(3)
        ])
        let original = projectedRawChildren(
            [rawLeaf("First").keyed("first"), rawLeaf("Second").keyed("second")],
            context: context, runtime: runtime)
        for node in original { parent.addChild(node) }
        let first = try XCTUnwrap(original.first)
        let second = try XCTUnwrap(original.last)
        let scope = context.retainedViewIdentity.appending(.role(.content))
        XCTAssertEqual(first.retainedViewIdentity, scope.appending(.keyed(.init("first"))))
        XCTAssertEqual(second.retainedViewIdentity, scope.appending(.keyed(.init("second"))))

        let replacement = projectedRawChildren(
            [rawLeaf("Second updated").keyed("second"), rawLeaf("First updated").keyed("first")],
            context: context, runtime: runtime)
        ComponentHost.reconcileChildren(of: parent, oldChildren: parent.children, newNodes: replacement)

        XCTAssertTrue(parent.children.first === second)
        XCTAssertTrue(parent.children.last === first)
        XCTAssertEqual(parent.children.map(\.text), ["Second updated", "First updated"])
    }

    func testDuplicateRawTagsRetainFIFOWithoutConsumingAnotherKey() async throws {
        let parent = ViewNode()
        let runtime = RetainedViewRuntime(root: parent)
        let context = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}).withViewIdentityPrefix([
            .slot(3)
        ])
        let original = projectedRawChildren(
            [
                rawLeaf("First shared").keyed("shared"),
                rawLeaf("Unique").keyed("unique"),
                rawLeaf("Second shared").keyed("shared"),
            ], context: context, runtime: runtime)
        for node in original { parent.addChild(node) }
        let firstShared = try XCTUnwrap(original.first)
        let unique = try XCTUnwrap(original.dropFirst().first)
        let secondShared = try XCTUnwrap(original.last)
        XCTAssertEqual(firstShared.retainedViewIdentity, secondShared.retainedViewIdentity)
        XCTAssertNotEqual(firstShared.retainedViewIdentity, unique.retainedViewIdentity)

        let replacement = projectedRawChildren(
            [
                rawLeaf("Updated first shared").keyed("shared"),
                rawLeaf("Updated second shared").keyed("shared"),
                rawLeaf("Updated unique").keyed("unique"),
            ], context: context, runtime: runtime)
        ComponentHost.reconcileChildren(of: parent, oldChildren: parent.children, newNodes: replacement)

        XCTAssertTrue(parent.children.first === firstShared)
        XCTAssertTrue(parent.children.dropFirst().first === secondShared)
        XCTAssertTrue(parent.children.last === unique)
        XCTAssertEqual(
            parent.children.map(\.text), ["Updated first shared", "Updated second shared", "Updated unique"])
    }

    func testRawUntaggedChildrenUseLocalSlotsAndDoNotTouchExistingPrefix() async throws {
        let parent = ViewNode()
        let runtime = RetainedViewRuntime(root: parent)
        let context = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}).withViewIdentityPrefix([
            .slot(3)
        ])
        let prefix = ViewNode()
        let original = projectedRawChildren(
            [rawLeaf("First"), rawLeaf("Second")], context: context, runtime: runtime, prefix: [prefix])
        XCTAssertEqual(original.count, 3)
        XCTAssertTrue(original.first === prefix)
        XCTAssertNil(prefix.retainedViewIdentity)
        let first = try XCTUnwrap(original.dropFirst().first)
        let second = try XCTUnwrap(original.last)
        let scope = context.retainedViewIdentity.appending(.role(.content))
        XCTAssertEqual(first.retainedViewIdentity, scope.appending(.slot(0)))
        XCTAssertEqual(second.retainedViewIdentity, scope.appending(.slot(1)))
        parent.addChild(first)
        parent.addChild(second)

        let replacement = projectedRawChildren(
            [rawLeaf("First updated"), rawLeaf("Second updated")], context: context, runtime: runtime)
        ComponentHost.reconcileChildren(of: parent, oldChildren: parent.children, newNodes: replacement)

        XCTAssertTrue(parent.children.first === first)
        XCTAssertTrue(parent.children.last === second)
        XCTAssertEqual(parent.children.map(\.text), ["First updated", "Second updated"])
    }

    func testExplicitChildIdentityWinsOverRawKeyAndChangingLocalSlot() async throws {
        let parent = ViewNode()
        let runtime = RetainedViewRuntime(root: parent)
        let context = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {}).withViewIdentityPrefix([
            .slot(3)
        ])
        let identity = context.retainedViewIdentity.appending(.role(.body)).appending(.keyed(.init(42)))
        let original = projectedRawChildren(
            [rawLeaf("Explicit", identity: identity).keyed("old-tag"), rawLeaf("Raw").keyed("raw")],
            context: context, runtime: runtime)
        for node in original { parent.addChild(node) }
        let explicit = try XCTUnwrap(original.first)
        let raw = try XCTUnwrap(original.last)
        XCTAssertEqual(explicit.retainedViewIdentity, identity)

        let replacement = projectedRawChildren(
            [rawLeaf("Raw updated").keyed("raw"), rawLeaf("Explicit updated", identity: identity).keyed("new-tag")],
            context: context, runtime: runtime)
        ComponentHost.reconcileChildren(of: parent, oldChildren: parent.children, newNodes: replacement)

        XCTAssertTrue(parent.children.first === raw)
        XCTAssertTrue(parent.children.last === explicit)
        XCTAssertEqual(explicit.retainedViewIdentity, identity)
        XCTAssertEqual(explicit.nodeTag, "new-tag")
        XCTAssertEqual(explicit.text, "Explicit updated")
    }

    private func rawLeaf(_ text: String, identity: RetainedViewIdentity? = nil) -> Component {
        Component { _ in
            let node = ViewNode(text: text)
            node.retainedViewIdentity = identity
            return node
        }
    }

    private func projectedRawChildren(
        _ children: [Component], context: ViewBuildContext, runtime: RetainedViewRuntime, prefix: [ViewNode] = []
    ) -> [ViewNode] {
        let source = Component(
            makeViewNode: { runtime in Controls.panel(children: children.map { $0.makeNode(runtime: runtime) }) },
            appendStructuralChildren: { runtime, nodes in
                for child in children { child.appendChildNodes(runtime: runtime, to: &nodes) }
            }
        )
        let component = preservingViewIdentity(of: source, context: context)
        var nodes = prefix
        component.appendChildNodes(runtime: runtime, to: &nodes)
        return nodes
    }
}
@MainActor
private final class StructuralCompositionRecorder {
    var componentCalls = 0
    var fallbackCalls = 0
    var appendCalls = 0
}
@MainActor
private struct StructuralCompositionProbe: View {
    let recorder: StructuralCompositionRecorder

    var body: Never { fatalError("The custom makeComponent implementation must be used.") }

    func makeComponent(context: ViewBuildContext) -> Component {
        recorder.componentCalls += 1
        return Component(
            makeViewNode: { _ in
                recorder.fallbackCalls += 1
                return Controls.panel(children: [ViewNode(text: "first"), ViewNode(text: "second")])
            },
            appendStructuralChildren: { _, nodes in
                recorder.appendCalls += 1
                nodes.append(contentsOf: [ViewNode(text: "first"), ViewNode(text: "second")])
            }
        )
    }
}
