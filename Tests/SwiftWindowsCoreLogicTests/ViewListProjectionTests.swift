import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewListProjectionTests: XCTestCase {
    func testExplicitLegacyArrayHelpersKeepHistoricalIdentityPrefixes() async throws {
        let leaf = AnyView(Text("Leaf"))
        let expression: [AnyView] = ViewBuilder.buildExpression([leaf, leaf])
        let viewExpression: [AnyView] = ViewBuilder.buildExpression(Text("Single"))
        let block: [AnyView] = ViewBuilder.buildBlock(expression)
        let first = try XCTUnwrap(block.first)
        let repeated: [AnyView] = ViewBuilder.buildBlock([first, first])
        let optional: [AnyView] = ViewBuilder.buildOptional([first])
        let either: [AnyView] = ViewBuilder.buildEither(second: [first])
        let loop: [AnyView] = ViewBuilder.buildArray([[first], [], [first]])
        let available: [AnyView] = ViewBuilder.buildLimitedAvailability(block)

        XCTAssertEqual(
            expression.map(\.structuralIdentity), [[.occurrence(0), .slot(0)], [.occurrence(0), .slot(1)]])
        XCTAssertEqual(viewExpression.map(\.structuralIdentity), [[]])
        XCTAssertEqual(
            block.map(\.structuralIdentity),
            [
                [.slot(0), .occurrence(0), .occurrence(0), .slot(0)],
                [.slot(0), .occurrence(0), .occurrence(0), .slot(1)],
            ])
        XCTAssertEqual(
            repeated.map(\.structuralIdentity),
            [
                [.slot(0), .occurrence(0), .slot(0), .occurrence(0), .occurrence(0), .slot(0)],
                [.slot(0), .occurrence(1), .slot(0), .occurrence(0), .occurrence(0), .slot(0)],
            ])
        XCTAssertEqual(optional.map(\.structuralIdentity), [[.branch(true)] + first.structuralIdentity])
        XCTAssertEqual(either.map(\.structuralIdentity), [[.branch(false)] + first.structuralIdentity])
        XCTAssertEqual(
            loop.map(\.structuralIdentity),
            [[.iteration(0)] + first.structuralIdentity, [.iteration(2)] + first.structuralIdentity])
        XCTAssertEqual(available.map(\.structuralIdentity), block.map(\.structuralIdentity))
    }

    func testProjectionKeepsCustomBodiesDelayedAndPreservesLeafTags() async {
        let recorder = ProjectionBodyRecorder()
        let value = TupleView(
            (
                ProjectionDelayedLeaf("First", recorder: recorder).tag("first"),
                ProjectionDelayedLeaf("Second", recorder: recorder).tag("second")
            ))

        let rows = materializedViewList(projectedViewList(value))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.selectionTag), [AnyHashable("first"), AnyHashable("second")])
        XCTAssertEqual(recorder.calls, 0)

        let context = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {})
        let runtime = RetainedViewRuntime(root: ViewNode())
        let component = makeViewComponent(value, context: context)
        XCTAssertEqual(recorder.calls, 0, "Creating a multi-child component must not build its leaves yet.")
        var nodes: [ViewNode] = []
        component.appendChildNodes(runtime: runtime, to: &nodes)

        XCTAssertEqual(nodes.map(\.text), ["First", "Second"])
        XCTAssertEqual(recorder.calls, 2)
    }

    func testCurrentErasurePrefixIsAppliedOnceAndOldCopiesKeepTheirPrefix() async {
        let tuple = TupleView((Text("First"), Text("Second")))
        var erased = AnyView(tuple).prefixedViewIdentity([.slot(41)])
        let old = AnyView(AnyView(erased))
        erased.structuralIdentity = [.slot(42)]

        let oldRows = materializedViewList(projectedViewList(old))
        let newRows = materializedViewList(projectedViewList(AnyView(erased)))

        XCTAssertEqual(oldRows.count, 2)
        XCTAssertEqual(newRows.count, 2)
        for row in oldRows {
            XCTAssertEqual(row.structuralIdentity.first, .slot(41))
            XCTAssertEqual(row.structuralIdentity.filter { $0 == .slot(41) }.count, 1)
            XCTAssertFalse(row.structuralIdentity.contains(.slot(42)))
        }
        for row in newRows {
            XCTAssertEqual(row.structuralIdentity.first, .slot(42))
            XCTAssertEqual(row.structuralIdentity.filter { $0 == .slot(42) }.count, 1)
            XCTAssertFalse(row.structuralIdentity.contains(.slot(41)))
        }
    }

    func testEmptyPrefixPreservesCurrentTypeButARealPrefixStartsANewOccurrence() async throws {
        let identifier = ObjectIdentifier(TupleView<(Text, Text)>.self)
        func projection(prefix: [RetainedViewIdentity.Segment]) -> ViewListProjection {
            .scope(
                .type(identifier), excluding: nil,
                children: [
                    .scope(
                        .prefix(prefix), excluding: nil,
                        children: [.scope(.type(identifier), excluding: nil, children: [.leaf(AnyView(Text("Leaf")))])])
                ])
        }

        let unchanged = try XCTUnwrap(materializedViewList(projection(prefix: []), startingType: identifier).first)
        let newOccurrence = try XCTUnwrap(
            materializedViewList(projection(prefix: [.slot(5)]), startingType: identifier).first)

        XCTAssertTrue(unchanged.structuralIdentity.isEmpty)
        XCTAssertEqual(newOccurrence.structuralIdentity, [.slot(5), .view(identifier)])
    }

    func testTupleDeclarationsPreserveCurrentNodesAndExcludeRemovedOptionalWithoutReadingBodies() async throws {
        let recorder = ProjectionBodyRecorder()
        var tuple = TupleView(
            (
                Optional(ProjectionDelayedLeaf("Optional", recorder: recorder)),
                ProjectionDelayedLeaf("Following", recorder: recorder)
            ))
        let context = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {})
            .withViewIdentityPrefix([.slot(9)])
        let runtime = RetainedViewRuntime(root: ViewNode())
        var nodes: [ViewNode] = []
        tuple.makeComponent(context: context).appendChildNodes(runtime: runtime, to: &nodes)
        let optional = try XCTUnwrap(nodes.first?.retainedViewIdentity)
        let following = try XCTUnwrap(nodes.last?.retainedViewIdentity)
        XCTAssertEqual(nodes.map(\.text), ["Optional", "Following"])
        XCTAssertEqual(recorder.calls, 2)

        let originalScopes = tuple.declaredStateMountScopes(context: context)
        XCTAssertTrue(originalScopes.contains { $0.contains(optional) })
        XCTAssertTrue(originalScopes.contains { $0.contains(following) })
        tuple.value.0 = nil
        let currentScopes = tuple.declaredStateMountScopes(context: context)

        XCTAssertFalse(currentScopes.contains { $0.contains(optional) })
        XCTAssertTrue(currentScopes.contains { $0.contains(following) })
        XCTAssertEqual(recorder.calls, 2, "Current declarations must not evaluate a custom body.")
    }

    func testLoopSlotsAreAssignedBeforeEmptyEntriesAndRemovedIterationIsExcluded() async throws {
        let recorder = ProjectionBodyRecorder()
        let first = ProjectionDelayedLeaf("First", recorder: recorder)
        let last = ProjectionDelayedLeaf("Last", recorder: recorder)
        let original = ViewBuilder.buildArray([Optional(first), nil, Optional(last)])
        let context = ViewBuildContext(canvasSizeProvider: { .zero }, invalidateHandler: {})
            .withViewIdentityPrefix([.slot(9)])
        let runtime = RetainedViewRuntime(root: ViewNode())
        var nodes: [ViewNode] = []
        original.makeComponent(context: context).appendChildNodes(runtime: runtime, to: &nodes)
        let firstIdentity = try XCTUnwrap(nodes.first?.retainedViewIdentity)
        let lastIdentity = try XCTUnwrap(nodes.last?.retainedViewIdentity)
        XCTAssertEqual(nodes.map(\.text), ["First", "Last"])
        XCTAssertTrue(firstIdentity.segments.contains(.iteration(0)))
        XCTAssertTrue(lastIdentity.segments.contains(.iteration(2)))
        XCTAssertFalse(lastIdentity.segments.contains(.iteration(1)))

        let current = ViewBuilder.buildArray([Optional(first), nil])
        let scopes = current.declaredStateMountScopes(context: context)

        XCTAssertTrue(scopes.contains { $0.contains(firstIdentity) })
        XCTAssertFalse(scopes.contains { $0.contains(lastIdentity) })
        XCTAssertEqual(recorder.calls, 2)
    }

    func testNodeAndMetadataDecoratorsRemainOpaqueDuringProjection() async {
        let recorder = ProjectionBodyRecorder()
        let tuple = TupleView(
            (ProjectionDelayedLeaf("First", recorder: recorder), ProjectionDelayedLeaf("Second", recorder: recorder)))
        let decorated = tuple.frame(width: 40, height: 30).id("aggregate").tag("aggregate")

        let rows = materializedViewList(projectedViewList(decorated))

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.selectionTag, AnyHashable("aggregate"))
        XCTAssertEqual(recorder.calls, 0)
    }

    func testKnownStructureExpansionIsDrivenByTheWalker() async {
        let recorder = ProjectionExpansionRecorder()
        var nested = ProjectionExpansionNode(child: nil, recorder: recorder)
        for _ in 0..<128 { nested = ProjectionExpansionNode(child: nested, recorder: recorder) }

        let projection = projectedViewList(nested)
        XCTAssertEqual(recorder.calls, 0, "Obtaining the root projection must not open descendants eagerly.")
        let rows = materializedViewList(projection)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(recorder.calls, 129)
        XCTAssertEqual(recorder.maximumActiveCalls, 1)
        XCTAssertEqual(recorder.activeCalls, 0)
    }
}

@MainActor
private final class ProjectionBodyRecorder {
    var calls = 0
}

private struct ProjectionDelayedLeaf: View {
    let label: String
    let recorder: ProjectionBodyRecorder

    init(_ label: String, recorder: ProjectionBodyRecorder) {
        self.label = label
        self.recorder = recorder
    }

    var body: Text {
        recorder.calls += 1
        return Text(label)
    }
}

@MainActor
private final class ProjectionExpansionRecorder {
    var calls = 0
    var activeCalls = 0
    var maximumActiveCalls = 0
}

@MainActor
private final class ProjectionExpansionNode: View, ViewListProjectionProvider {
    let child: ProjectionExpansionNode?
    let recorder: ProjectionExpansionRecorder

    init(child: ProjectionExpansionNode?, recorder: ProjectionExpansionRecorder) {
        self.child = child
        self.recorder = recorder
    }

    var body: Never { fatalError("The projection node has no body") }

    func viewListProjection() -> ViewListProjection {
        recorder.calls += 1
        recorder.activeCalls += 1
        recorder.maximumActiveCalls = max(recorder.maximumActiveCalls, recorder.activeCalls)
        defer { recorder.activeCalls -= 1 }
        if let child {
            return .scope(.prefix([.slot(0)]), excluding: nil, children: [projectedViewList(child)])
        }
        return .leaf(AnyView(Text("Leaf")))
    }
}
