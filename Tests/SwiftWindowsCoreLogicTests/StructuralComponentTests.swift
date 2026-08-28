import XCTest

@testable import SwiftWindowsUI

@MainActor
final class StructuralComponentTests: XCTestCase {
    func testLeafAppendsExactlyOneFreshNodeAndPreservesExistingPrefix() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let prefix = ViewNode()
        var constructedNodes: [ViewNode] = []
        let component = Component { receivedRuntime in
            XCTAssertTrue(receivedRuntime === runtime)
            let node = ViewNode()
            constructedNodes.append(node)
            return node
        }

        XCTAssertFalse(component.hasStructuralChildren)
        XCTAssertTrue(constructedNodes.isEmpty)

        var nodes = [prefix]
        component.appendChildNodes(runtime: runtime, to: &nodes)
        XCTAssertEqual(constructedNodes.count, 1)
        assertSameNodes(nodes, [prefix] + constructedNodes)

        component.appendChildNodes(runtime: runtime, to: &nodes)
        XCTAssertEqual(constructedNodes.count, 2)
        assertSameNodes(nodes, [prefix] + constructedNodes)
        XCTAssertFalse(constructedNodes.first === constructedNodes.last)
        XCTAssertNil(prefix.nodeTag)
    }

    func testStructuralAppendUsesOnlyListConstructorAndPreservesOrder() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let prefix = ViewNode()
        var fallbackCalls = 0
        var listCalls = 0
        var constructedNodes: [ViewNode] = []
        let component = Component(
            makeViewNode: { _ in
                fallbackCalls += 1
                return ViewNode()
            },
            appendStructuralChildren: { receivedRuntime, nodes in
                XCTAssertTrue(receivedRuntime === runtime)
                listCalls += 1
                let first = ViewNode()
                let second = ViewNode()
                constructedNodes.append(contentsOf: [first, second])
                nodes.append(contentsOf: [first, second])
            }
        )

        XCTAssertTrue(component.hasStructuralChildren)
        XCTAssertEqual(fallbackCalls, 0)
        XCTAssertEqual(listCalls, 0)

        var nodes = [prefix]
        component.appendChildNodes(runtime: runtime, to: &nodes)
        XCTAssertEqual(fallbackCalls, 0)
        XCTAssertEqual(listCalls, 1)
        XCTAssertEqual(constructedNodes.count, 2)
        assertSameNodes(nodes, [prefix] + constructedNodes)

        component.appendChildNodes(runtime: runtime, to: &nodes)
        XCTAssertEqual(fallbackCalls, 0)
        XCTAssertEqual(listCalls, 2)
        XCTAssertEqual(constructedNodes.count, 4)
        assertSameNodes(nodes, [prefix] + constructedNodes)
    }

    func testEmptyStructuralListDoesNotUseFallback() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let prefix = ViewNode()
        var fallbackCalls = 0
        var listCalls = 0
        let emptyList = Component(
            makeViewNode: { _ in
                fallbackCalls += 1
                return ViewNode()
            },
            appendStructuralChildren: { _, _ in
                listCalls += 1
            }
        )

        XCTAssertTrue(emptyList.hasStructuralChildren)
        var nodes = [prefix]
        emptyList.appendChildNodes(runtime: runtime, to: &nodes)
        emptyList.appendChildNodes(runtime: runtime, to: &nodes)

        XCTAssertEqual(listCalls, 2)
        XCTAssertEqual(fallbackCalls, 0)
        assertSameNodes(nodes, [prefix])

        XCTAssertFalse(Component.empty.hasStructuralChildren)
        Component.empty.appendChildNodes(runtime: runtime, to: &nodes)
        XCTAssertEqual(nodes.count, 2)
        XCTAssertTrue(nodes.first === prefix)
        XCTAssertFalse(nodes.last === prefix)
    }

    func testMakeNodeUsesFallbackWithoutExpandingStructuralChildren() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let aggregate = ViewNode()
        let child = ViewNode()
        var fallbackCalls = 0
        var listCalls = 0
        let component = Component(
            makeViewNode: { receivedRuntime in
                XCTAssertTrue(receivedRuntime === runtime)
                fallbackCalls += 1
                return aggregate
            },
            appendStructuralChildren: { _, nodes in
                listCalls += 1
                nodes.append(child)
            }
        )

        XCTAssertTrue(component.makeNode(runtime: runtime) === aggregate)
        XCTAssertEqual(fallbackCalls, 1)
        XCTAssertEqual(listCalls, 0)
        XCTAssertTrue(component.hasStructuralChildren)

        var nodes: [ViewNode] = []
        component.appendChildNodes(runtime: runtime, to: &nodes)
        assertSameNodes(nodes, [child])
        XCTAssertEqual(fallbackCalls, 1)
        XCTAssertEqual(listCalls, 1)
    }

    func testKeyedStructuralComponentKeepsOneAggregateAndDoesNotTagItsChildren() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let prefix = ViewNode()
        let firstChild = ViewNode()
        let secondChild = ViewNode()
        secondChild.nodeTag = "child-key"
        var constructedAggregates: [ViewNode] = []
        var listCalls = 0
        let component = Component(
            key: "aggregate-key",
            makeViewNode: { receivedRuntime in
                XCTAssertTrue(receivedRuntime === runtime)
                let aggregate = ViewNode()
                aggregate.addChild(firstChild)
                aggregate.addChild(secondChild)
                constructedAggregates.append(aggregate)
                return aggregate
            },
            appendStructuralChildren: { _, nodes in
                listCalls += 1
                nodes.append(contentsOf: [firstChild, secondChild])
            }
        )

        XCTAssertFalse(component.hasStructuralChildren)
        XCTAssertTrue(constructedAggregates.isEmpty)
        XCTAssertEqual(listCalls, 0)

        var nodes = [prefix]
        component.appendChildNodes(runtime: runtime, to: &nodes)

        XCTAssertEqual(constructedAggregates.count, 1)
        assertSameNodes(nodes, [prefix] + constructedAggregates)
        XCTAssertEqual(constructedAggregates.first?.nodeTag, "aggregate-key")
        assertSameNodes(constructedAggregates.first?.children ?? [], [firstChild, secondChild])
        XCTAssertEqual(listCalls, 0)
        XCTAssertNil(prefix.nodeTag)
        XCTAssertNil(firstChild.nodeTag)
        XCTAssertEqual(secondChild.nodeTag, "child-key")
    }

    func testKeyedFallbackPreservesAnExistingNodeTag() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let aggregate = ViewNode()
        aggregate.nodeTag = "existing-key"
        var fallbackCalls = 0
        var listCalls = 0
        let component = Component(
            key: "component-key",
            makeViewNode: { _ in
                fallbackCalls += 1
                return aggregate
            },
            appendStructuralChildren: { _, _ in
                listCalls += 1
            }
        )

        var nodes: [ViewNode] = []
        component.appendChildNodes(runtime: runtime, to: &nodes)

        assertSameNodes(nodes, [aggregate])
        XCTAssertEqual(aggregate.nodeTag, "existing-key")
        XCTAssertEqual(fallbackCalls, 1)
        XCTAssertEqual(listCalls, 0)
    }

    func testKeyedCopyCanRestoreListCapabilityWithoutChangingOriginal() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let child = ViewNode()
        var constructedAggregates: [ViewNode] = []
        var listCalls = 0
        let original = Component(
            makeViewNode: { _ in
                let aggregate = ViewNode()
                constructedAggregates.append(aggregate)
                return aggregate
            },
            appendStructuralChildren: { _, nodes in
                listCalls += 1
                nodes.append(child)
            }
        )
        var keyed = original.keyed("aggregate-key")

        XCTAssertTrue(original.hasStructuralChildren)
        XCTAssertNil(original.key)
        XCTAssertFalse(keyed.hasStructuralChildren)
        XCTAssertEqual(keyed.key, "aggregate-key")

        var nodes: [ViewNode] = []
        keyed.appendChildNodes(runtime: runtime, to: &nodes)
        XCTAssertEqual(constructedAggregates.count, 1)
        XCTAssertEqual(constructedAggregates.first?.nodeTag, "aggregate-key")
        XCTAssertEqual(listCalls, 0)

        keyed.key = ""
        XCTAssertFalse(keyed.hasStructuralChildren, "an empty string is still a reconciliation key")
        keyed.appendChildNodes(runtime: runtime, to: &nodes)
        XCTAssertEqual(constructedAggregates.count, 2)
        XCTAssertEqual(constructedAggregates.last?.nodeTag, "")
        XCTAssertEqual(listCalls, 0)

        keyed.key = nil
        XCTAssertTrue(keyed.hasStructuralChildren)
        keyed.appendChildNodes(runtime: runtime, to: &nodes)
        XCTAssertEqual(constructedAggregates.count, 2)
        XCTAssertEqual(listCalls, 1)
        assertSameNodes(nodes, constructedAggregates + [child])
        XCTAssertNil(child.nodeTag)
        XCTAssertTrue(original.hasStructuralChildren)
        XCTAssertNil(original.key)
    }

    func testAsSingleNodeOnlyStripsCapabilityFromReturnedCopy() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let prefix = ViewNode()
        let aggregate = ViewNode()
        let firstChild = ViewNode()
        let secondChild = ViewNode()
        var fallbackCalls = 0
        var listCalls = 0
        let original = Component(
            makeViewNode: { _ in
                fallbackCalls += 1
                return aggregate
            },
            appendStructuralChildren: { _, nodes in
                listCalls += 1
                nodes.append(contentsOf: [firstChild, secondChild])
            }
        )
        let single = original.asSingleNode()

        XCTAssertTrue(original.hasStructuralChildren)
        XCTAssertFalse(single.hasStructuralChildren)
        XCTAssertNil(single.key)
        XCTAssertEqual(fallbackCalls, 0)
        XCTAssertEqual(listCalls, 0)

        var nodes = [prefix]
        single.appendChildNodes(runtime: runtime, to: &nodes)
        assertSameNodes(nodes, [prefix, aggregate])
        XCTAssertEqual(fallbackCalls, 1)
        XCTAssertEqual(listCalls, 0)

        original.appendChildNodes(runtime: runtime, to: &nodes)
        assertSameNodes(nodes, [prefix, aggregate, firstChild, secondChild])
        XCTAssertEqual(fallbackCalls, 1)
        XCTAssertEqual(listCalls, 1)

        let singleAgain = single.asSingleNode()
        XCTAssertFalse(singleAgain.hasStructuralChildren)
        XCTAssertTrue(singleAgain.makeNode(runtime: runtime) === aggregate)
        XCTAssertEqual(fallbackCalls, 2)
        XCTAssertEqual(listCalls, 1)
    }

    func testAsSingleNodePreservesKeyAndDoesNotRestoreCapabilityWhenKeyIsCleared() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        var constructedAggregates: [ViewNode] = []
        var listCalls = 0
        var original = Component(
            key: "aggregate-key",
            makeViewNode: { _ in
                let aggregate = ViewNode()
                constructedAggregates.append(aggregate)
                return aggregate
            },
            appendStructuralChildren: { _, _ in
                listCalls += 1
            }
        )
        var single = original.asSingleNode()

        XCTAssertEqual(single.key, "aggregate-key")
        XCTAssertFalse(single.hasStructuralChildren)
        var nodes: [ViewNode] = []
        single.appendChildNodes(runtime: runtime, to: &nodes)
        XCTAssertEqual(constructedAggregates.count, 1)
        XCTAssertEqual(constructedAggregates.first?.nodeTag, "aggregate-key")

        single.key = nil
        XCTAssertFalse(single.hasStructuralChildren)
        single.appendChildNodes(runtime: runtime, to: &nodes)
        XCTAssertEqual(constructedAggregates.count, 2)
        XCTAssertNil(constructedAggregates.last?.nodeTag)
        assertSameNodes(nodes, constructedAggregates)
        XCTAssertEqual(listCalls, 0)

        original.key = nil
        XCTAssertTrue(original.hasStructuralChildren)
        original.appendChildNodes(runtime: runtime, to: &nodes)
        assertSameNodes(nodes, constructedAggregates)
        XCTAssertEqual(listCalls, 1)
    }

    func testNestedStructuralProducersAppendInOrderWithoutBuildingAggregates() async {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let prefix = ViewNode()
        var events: [String] = []
        var constructedLeaves: [ViewNode] = []

        func leaf(_ name: String) -> Component {
            Component { receivedRuntime in
                XCTAssertTrue(receivedRuntime === runtime)
                events.append(name)
                let node = ViewNode()
                constructedLeaves.append(node)
                return node
            }
        }

        let first = leaf("first")
        let middleA = leaf("middle-a")
        let middleB = leaf("middle-b")
        let last = leaf("last")
        let middle = Component(
            makeViewNode: { _ in
                events.append("middle-fallback")
                return ViewNode()
            },
            appendStructuralChildren: { receivedRuntime, nodes in
                events.append("middle-list")
                middleA.appendChildNodes(runtime: receivedRuntime, to: &nodes)
                middleB.appendChildNodes(runtime: receivedRuntime, to: &nodes)
            }
        )
        let empty = Component(
            makeViewNode: { _ in
                events.append("empty-fallback")
                return ViewNode()
            },
            appendStructuralChildren: { _, _ in
                events.append("empty-list")
            }
        )
        let outer = Component(
            makeViewNode: { _ in
                events.append("outer-fallback")
                return ViewNode()
            },
            appendStructuralChildren: { receivedRuntime, nodes in
                events.append("outer-list")
                first.appendChildNodes(runtime: receivedRuntime, to: &nodes)
                middle.appendChildNodes(runtime: receivedRuntime, to: &nodes)
                empty.appendChildNodes(runtime: receivedRuntime, to: &nodes)
                last.appendChildNodes(runtime: receivedRuntime, to: &nodes)
            }
        )

        XCTAssertTrue(events.isEmpty)
        var nodes = [prefix]
        outer.appendChildNodes(runtime: runtime, to: &nodes)

        XCTAssertEqual(
            events,
            ["outer-list", "first", "middle-list", "middle-a", "middle-b", "empty-list", "last"]
        )
        XCTAssertEqual(constructedLeaves.count, 4)
        assertSameNodes(nodes, [prefix] + constructedLeaves)
    }

    private func assertSameNodes(
        _ actual: [ViewNode],
        _ expected: [ViewNode],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.map { ObjectIdentifier($0) },
            expected.map { ObjectIdentifier($0) },
            file: file,
            line: line
        )
    }
}
