import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedViewIdentityTests: XCTestCase {
    func testKeysCompareDeclaredTypeAndValueInsteadOfDescription() async {
        let first = RetainedIdentityFirstKey(value: 1)
        let second = RetainedIdentityFirstKey(value: 2)
        let otherType = RetainedIdentitySecondKey(value: 1)
        XCTAssertEqual(first.description, second.description)
        XCTAssertEqual(first.description, otherType.description)

        let keys: Set<RetainedViewIdentity.Key> = [
            .init(first),
            .init(second),
            .init(otherType),
            .init(Int8(1)),
            .init(Int64(1)),
        ]
        XCTAssertEqual(keys.count, 5)
        XCTAssertEqual(RetainedViewIdentity.Key(first), .init(RetainedIdentityFirstKey(value: 1)))
    }

    func testAppendingPreservesOrderedStructuralSegmentsWithoutMutatingParent() async {
        let parent = RetainedViewIdentity(segments: [.view(ObjectIdentifier(RetainedIdentityOwner.self))])
        let child = parent.appending(.role(.content)).appending(contentsOf: [.slot(2), .branch(true)])
        XCTAssertEqual(parent.segments, [.view(ObjectIdentifier(RetainedIdentityOwner.self))])
        XCTAssertEqual(
            child.segments,
            [.view(ObjectIdentifier(RetainedIdentityOwner.self)), .role(.content), .slot(2), .branch(true)])
        XCTAssertEqual(child.appending(contentsOf: []), child)

        let variants: Set<RetainedViewIdentity> = [
            parent.appending(.slot(1)),
            parent.appending(.iteration(1)),
            parent.appending(.keyed(.init(1))),
            parent.appending(.explicit(.init(1))),
            parent.appending(.branch(true)),
            parent.appending(.branch(false)),
            parent.appending(.role(.header)),
            parent.appending(.role(.footer)),
            parent.appending(contentsOf: [.slot(1), .slot(2)]),
            parent.appending(contentsOf: [.slot(2), .slot(1)]),
        ]
        XCTAssertEqual(variants.count, 10)
    }

    func testTypedReorderWinsOverEqualTagsAndPreservesFocusAndScrollOffset() async {
        let firstIdentity = identity(RetainedIdentityFirstKey(value: 1))
        let secondIdentity = identity(RetainedIdentityFirstKey(value: 2))
        let first = node(identity: firstIdentity, tag: "same", text: "first")
        let second = node(identity: secondIdentity, tag: "same", text: "second")
        let runtime = runtime(children: [first, second])
        first.scrollOffset = 37
        runtime.requestFocus(first)
        XCTAssertTrue(runtime.focusedNode === first)

        let nextSecond = node(identity: secondIdentity, tag: "same", text: "second updated")
        let nextFirst = node(identity: firstIdentity, tag: "same", text: "first updated")
        reconcile(runtime.root, with: [nextSecond, nextFirst])

        XCTAssertTrue(runtime.root.children[0] === second)
        XCTAssertTrue(runtime.root.children[1] === first)
        XCTAssertEqual(first.text, "first updated")
        XCTAssertEqual(second.text, "second updated")
        XCTAssertEqual(first.scrollOffset, 37)
        XCTAssertTrue(runtime.focusedNode === first)
        XCTAssertTrue(first.parent === runtime.root)
        XCTAssertTrue(second.parent === runtime.root)
        XCTAssertTrue(runtime.transitionOverlays.isEmpty)
    }

    func testMatchingTypedIdentityCanUpdateTheLegacyTag() async {
        let viewIdentity = identity(1)
        let existing = node(identity: viewIdentity, tag: "before", text: "before")
        let runtime = runtime(children: [existing])
        let replacement = node(identity: viewIdentity, tag: "after", text: "after")

        reconcile(runtime.root, with: [replacement])

        XCTAssertTrue(runtime.root.children[0] === existing)
        XCTAssertEqual(existing.nodeTag, "after")
        XCTAssertEqual(existing.retainedViewIdentity, viewIdentity)
        XCTAssertEqual(existing.text, "after")
    }

    func testDifferentTypedIdentitiesDoNotMatchThroughEqualTagsOrLayout() async {
        for tag in [String?(nil), "same"] {
            let existing = node(identity: identity(RetainedIdentityFirstKey(value: 1)), tag: tag, text: "before")
            let runtime = runtime(children: [existing])
            runtime.requestFocus(existing)
            let replacement = node(identity: identity(RetainedIdentitySecondKey(value: 1)), tag: tag, text: "after")

            reconcile(runtime.root, with: [replacement])

            XCTAssertTrue(runtime.root.children[0] === replacement)
            XCTAssertNil(existing.parent)
            XCTAssertNil(runtime.focusedNode)
            XCTAssertEqual(existing.text, "before", "An unmatched node must not adopt the replacement's properties")
        }
    }

    func testTypedAndUntypedNodesNeverBridgeThroughTagsOrLayout() async {
        for startsTyped in [false, true] {
            for tag in [String?(nil), "same"] {
                let existing = node(identity: startsTyped ? RetainedViewIdentity() : nil, tag: tag)
                let runtime = runtime(children: [existing])
                let replacement = node(identity: startsTyped ? nil : RetainedViewIdentity(), tag: tag)

                reconcile(runtime.root, with: [replacement])

                XCTAssertTrue(runtime.root.children[0] === replacement)
                XCTAssertNil(existing.parent)
            }
        }
    }

    func testTypedAndLegacyNodesWithTheSameTagClaimSeparateOccurrences() async {
        let viewIdentity = identity(1)
        let typed = node(identity: viewIdentity, tag: "same", text: "typed")
        let legacy = node(tag: "same", text: "legacy")
        let runtime = runtime(children: [typed, legacy])

        reconcile(
            runtime.root,
            with: [
                node(tag: "same", text: "legacy updated"),
                node(identity: viewIdentity, tag: "same", text: "typed updated"),
            ])

        XCTAssertTrue(runtime.root.children[0] === legacy)
        XCTAssertTrue(runtime.root.children[1] === typed)
        XCTAssertEqual(legacy.text, "legacy updated")
        XCTAssertEqual(typed.text, "typed updated")
        XCTAssertNil(legacy.retainedViewIdentity)
        XCTAssertEqual(typed.retainedViewIdentity, viewIdentity)
    }

    func testDuplicateTypedIdentitiesClaimEachOldOccurrenceOnlyOnce() async {
        let viewIdentity = identity(1)
        let first = node(identity: viewIdentity, tag: "same", text: "first")
        let second = node(identity: viewIdentity, tag: "same", text: "second")
        let legacy = node(tag: "same", text: "legacy")
        let runtime = runtime(children: [first, legacy, second])
        let inserted = node(identity: viewIdentity, tag: "same", text: "inserted")

        reconcile(
            runtime.root,
            with: [
                node(identity: viewIdentity, tag: "same", text: "first updated"),
                node(identity: viewIdentity, tag: "same", text: "second updated"),
                inserted,
                node(tag: "same", text: "legacy updated"),
            ])

        XCTAssertEqual(runtime.root.children.count, 4)
        XCTAssertTrue(runtime.root.children[0] === first)
        XCTAssertTrue(runtime.root.children[1] === second)
        XCTAssertTrue(runtime.root.children[2] === inserted)
        XCTAssertTrue(runtime.root.children[3] === legacy)
        XCTAssertEqual(Set(runtime.root.children.map(ObjectIdentifier.init)).count, 4)
        XCTAssertEqual(first.text, "first updated")
        XCTAssertEqual(second.text, "second updated")
        XCTAssertTrue(runtime.root.children.allSatisfy { $0.parent === runtime.root })
    }

    func testDuplicateLegacyTagsStillClaimEachOldOccurrenceOnlyOnce() async {
        let first = node(tag: "same", text: "first")
        let second = node(tag: "same", text: "second")
        let runtime = runtime(children: [first, second])
        let inserted = node(tag: "same", text: "inserted")

        reconcile(
            runtime.root,
            with: [node(tag: "same", text: "first updated"), node(tag: "same", text: "second updated"), inserted])

        XCTAssertTrue(runtime.root.children[0] === first)
        XCTAssertTrue(runtime.root.children[1] === second)
        XCTAssertTrue(runtime.root.children[2] === inserted)
        XCTAssertEqual(Set(runtime.root.children.map(ObjectIdentifier.init)).count, 3)
    }

    func testLegacyTagsStillReorderAndUntaggedNodesStillMatchByPosition() async {
        let first = node(tag: "first")
        let positional = node(text: "positional")
        let second = node(tag: "second")
        let runtime = runtime(children: [first, positional, second])

        reconcile(
            runtime.root,
            with: [node(tag: "second"), node(text: "positional updated"), node(tag: "first")])

        XCTAssertTrue(runtime.root.children[0] === second)
        XCTAssertTrue(runtime.root.children[1] === positional)
        XCTAssertTrue(runtime.root.children[2] === first)
        XCTAssertEqual(positional.text, "positional updated")
    }

    func testLegacyOneSidedTagStillUsesItsExistingLayoutFallback() async {
        for startsTagged in [false, true] {
            let existing = node(tag: startsTagged ? "legacy" : nil)
            let runtime = runtime(children: [existing])
            let replacement = node(tag: startsTagged ? nil : "legacy", text: "updated")

            reconcile(runtime.root, with: [replacement])

            XCTAssertTrue(runtime.root.children[0] === existing)
            XCTAssertEqual(existing.nodeTag, replacement.nodeTag)
            XCTAssertEqual(existing.text, "updated")
        }
    }

    func testTypedInsertionsAndRemovalsPreserveSurvivingNodes() async {
        let first = node(identity: identity(1))
        let second = node(identity: identity(2))
        let third = node(identity: identity(3))
        let runtime = runtime(children: [first, second, third])
        let inserted = node(identity: identity(4))

        reconcile(runtime.root, with: [inserted, node(identity: identity(3)), node(identity: identity(2))])

        XCTAssertTrue(runtime.root.children[0] === inserted)
        XCTAssertTrue(runtime.root.children[1] === third)
        XCTAssertTrue(runtime.root.children[2] === second)
        XCTAssertNil(first.parent)
        XCTAssertTrue(runtime.root.children.allSatisfy { $0.parent === runtime.root })
    }

    func testNestedReconciliationRetainsTypedChildrenAndReparentsInsertions() async {
        let parentIdentity = identity("parent")
        let childIdentity = parentIdentity.appending(.keyed(.init("child")))
        let existingParent = node(identity: parentIdentity)
        let existingChild = node(identity: childIdentity, text: "before")
        existingParent.addChild(existingChild)
        let runtime = runtime(children: [existingParent])
        let replacementParent = node(identity: parentIdentity)
        let inserted = node(identity: parentIdentity.appending(.keyed(.init("inserted"))))
        replacementParent.addChild(inserted)
        replacementParent.addChild(node(identity: childIdentity, text: "after"))

        reconcile(runtime.root, with: [replacementParent])

        XCTAssertTrue(runtime.root.children[0] === existingParent)
        XCTAssertTrue(existingParent.children[0] === inserted)
        XCTAssertTrue(existingParent.children[1] === existingChild)
        XCTAssertTrue(inserted.parent === existingParent)
        XCTAssertTrue(existingChild.parent === existingParent)
        XCTAssertEqual(existingChild.text, "after")
        XCTAssertEqual(existingChild.retainedViewIdentity, childIdentity)
    }

    func testAdoptionCopiesAndClearsTypedIdentity() async {
        let existing = node(identity: identity("before"), tag: "before")
        let runtime = runtime(children: [existing])
        let replacement = node(identity: identity("after"), tag: "after")

        ComponentHost.adopt(source: replacement, into: existing)

        XCTAssertTrue(runtime.root.children[0] === existing)
        XCTAssertEqual(existing.retainedViewIdentity, replacement.retainedViewIdentity)
        XCTAssertEqual(existing.nodeTag, "after")

        ComponentHost.adopt(source: node(tag: "legacy"), into: existing)

        XCTAssertTrue(runtime.root.children[0] === existing)
        XCTAssertNil(existing.retainedViewIdentity)
        XCTAssertEqual(existing.nodeTag, "legacy")
    }

    func testDirectReparentingPreservesTypedIdentityAcrossRuntimes() async {
        let viewIdentity = identity(1)
        let moved = node(identity: viewIdentity, tag: "same")
        let source = runtime(children: [moved])
        let destination = runtime(children: [])

        destination.root.addChild(moved)

        XCTAssertTrue(source.root.children.isEmpty)
        XCTAssertTrue(destination.root.children.first === moved)
        XCTAssertTrue(moved.parent === destination.root)
        XCTAssertEqual(moved.retainedViewIdentity, viewIdentity)

        reconcile(destination.root, with: [node(identity: viewIdentity, tag: "updated")])

        XCTAssertTrue(destination.root.children.first === moved)
        XCTAssertEqual(moved.nodeTag, "updated")
        XCTAssertEqual(moved.retainedViewIdentity, viewIdentity)
    }

    private func identity<ID: Hashable>(_ key: ID) -> RetainedViewIdentity {
        RetainedViewIdentity(
            segments: [.view(ObjectIdentifier(RetainedIdentityOwner.self)), .role(.content), .keyed(.init(key))])
    }

    private func node(identity: RetainedViewIdentity? = nil, tag: String? = nil, text: String? = nil) -> ViewNode {
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 30), text: text)
        node.retainedViewIdentity = identity
        node.nodeTag = tag
        node.isFocusable = true
        return node
    }

    private func runtime(children: [ViewNode]) -> RetainedViewRuntime {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300)))
        for child in children {
            runtime.root.addChild(child)
        }
        return runtime
    }

    private func reconcile(_ parent: ViewNode, with children: [ViewNode]) {
        ComponentHost.reconcileChildren(of: parent, oldChildren: parent.children, newNodes: children)
    }
}

private struct RetainedIdentityOwner {}

private struct RetainedIdentityFirstKey: Hashable, CustomStringConvertible {
    let value: Int

    var description: String { "same" }

    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }
}

private struct RetainedIdentitySecondKey: Hashable, CustomStringConvertible {
    let value: Int

    var description: String { "same" }
}
