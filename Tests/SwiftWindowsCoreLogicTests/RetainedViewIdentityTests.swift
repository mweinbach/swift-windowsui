import SwiftWindowsCore
import SwiftWindowsLayout
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

    func testSingletonTypedIdentityRetainsStateAndAdoptsFreshConfiguration() async {
        let existing = node(identity: identity("parent"), tag: "old tag", text: "old text")
        let existingChild = node(identity: identity("child"), text: "old child")
        existing.addChild(existingChild)
        let previousController = SingletonIdentityTextInputController()
        existing.textInputController = previousController
        var callbacks: [String] = []
        existing.onActivate = { callbacks.append("old activation") }
        existing.onUpdatePlatformView = { _ in callbacks.append("old update") }
        let runtime = runtime(children: [existing])
        existing.scrollOffset = 37
        runtime.requestFocus(existing)

        let replacement = node(identity: identity("parent"), tag: "new tag", text: "new text")
        replacement.layoutMode = .stack(.horizontal(spacing: 12))
        replacement.addChild(node(identity: identity("child"), text: "new child"))
        let nextController = SingletonIdentityTextInputController()
        replacement.textInputController = nextController
        replacement.onActivate = { callbacks.append("new activation") }
        replacement.onUpdatePlatformView = { _ in callbacks.append("new update") }

        reconcile(runtime.root, with: [replacement])
        existing.onActivate?()

        XCTAssertTrue(runtime.root.children.first === existing)
        XCTAssertTrue(existing.parent === runtime.root)
        assertRuntimeClockRoute(existing, through: runtime, isAttached: true)
        XCTAssertTrue(runtime.focusedNode === existing)
        XCTAssertEqual(existing.scrollOffset, 37)
        XCTAssertEqual(existing.retainedViewIdentity, replacement.retainedViewIdentity)
        XCTAssertEqual(existing.nodeTag, "new tag")
        XCTAssertEqual(existing.text, "new text")
        XCTAssertEqual(existing.layoutMode.stackLayout?.axis, .horizontal)
        XCTAssertTrue(existing.children.first === existingChild)
        XCTAssertEqual(existingChild.text, "new child")
        XCTAssertEqual(callbacks, ["new update", "new activation"])
        XCTAssertTrue(existing.textInputController === nextController)
        XCTAssertEqual(nextController.preparationCount, 1)
        XCTAssertTrue(nextController.preparedPrevious === previousController)
        XCTAssertTrue(nextController.reconciledPrevious === previousController)
        XCTAssertTrue(nextController.preparedNode === existing)
        XCTAssertTrue(nextController.reconciledNode === existing)
        XCTAssertTrue(nextController.wasPreparedBeforeReconciliation)
        XCTAssertFalse(previousController.wasRevoked)
        XCTAssertFalse(previousController.didDetach)
    }

    func testSingletonLegacyTagsAndLayoutCategoriesKeepTheirMatchingPrecedence() async {
        let layouts: [(ViewLayoutMode, ViewLayoutMode)] = [
            (.absolute, .absolute),
            (.stack(.vertical(spacing: 2)), .stack(.vertical(spacing: 11))),
            (.stack(.horizontal(spacing: 3)), .stack(.horizontal(spacing: 12))),
            (.lazyStack(.vertical(spacing: 4)), .lazyStack(.vertical(spacing: 13))),
            (.lazyStack(.horizontal(spacing: 5)), .lazyStack(.horizontal(spacing: 14))),
            (.flex(.init(direction: .row)), .flex(.init(direction: .column))),
        ]
        let tags: [(String?, String?)] = [
            (nil, nil),
            ("same", "same"),
            ("before", "after"),
            ("one-sided", nil),
            (nil, "one-sided"),
        ]

        for (oldCategory, oldLayouts) in layouts.enumerated() {
            for (newCategory, newLayouts) in layouts.enumerated() {
                for (oldTag, newTag) in tags {
                    let existing = node(tag: oldTag, text: "original")
                    existing.layoutMode = oldLayouts.0
                    let runtime = runtime(children: [existing])
                    let replacement = node(tag: newTag, text: "updated")
                    replacement.layoutMode = newLayouts.1
                    let shouldMatch =
                        oldTag != nil && newTag != nil ? oldTag == newTag : oldCategory == newCategory
                    let tagContext = "\(String(describing: oldTag))/\(String(describing: newTag))"
                    let context = "layouts \(oldCategory)/\(newCategory), tags \(tagContext)"

                    reconcile(runtime.root, with: [replacement])

                    XCTAssertTrue(runtime.root.children.first === (shouldMatch ? existing : replacement), context)
                    XCTAssertEqual(existing.text, shouldMatch ? "updated" : "original", context)
                    if shouldMatch {
                        XCTAssertTrue(existing.parent === runtime.root, context)
                        XCTAssertEqual(existing.nodeTag, newTag, context)
                    } else {
                        XCTAssertNil(existing.parent, context)
                        assertRuntimeClockRoute(existing, through: runtime, isAttached: false, context)
                    }
                }
            }
        }
    }

    func testSingletonDepartureIsRevokedBeforeItsSurvivingParentsUpdateCallback() async {
        let existingParent = node(identity: identity("parent"), text: "old parent")
        let departingEditor = node(identity: identity("departing editor"))
        let departingController = SingletonIdentityTextInputController()
        departingEditor.textInputController = departingController
        existingParent.addChild(departingEditor)
        let runtime = runtime(children: [existingParent])
        runtime.requestFocus(departingEditor)
        var callbacks: [String] = []
        departingEditor.onFocusExit = {
            XCTAssertTrue(departingController.wasRevoked)
            callbacks.append("focus exit")
        }

        let replacementParent = node(identity: identity("parent"), text: "new parent")
        let insertedEditor = node(identity: identity("inserted editor"))
        let insertedController = SingletonIdentityTextInputController()
        insertedEditor.textInputController = insertedController
        replacementParent.addChild(insertedEditor)
        replacementParent.onUpdatePlatformView = { [weak existingParent, weak departingEditor, weak runtime] node in
            XCTAssertTrue(node === existingParent)
            XCTAssertTrue(departingController.wasRevoked)
            XCTAssertTrue(departingEditor?.parent === existingParent)
            assertRuntimeClockRoute(departingEditor, through: runtime, isAttached: true)
            callbacks.append("parent update")
        }

        reconcile(runtime.root, with: [replacementParent])

        XCTAssertEqual(callbacks, ["parent update", "focus exit"])
        XCTAssertTrue(runtime.root.children.first === existingParent)
        XCTAssertEqual(existingParent.text, "new parent")
        XCTAssertTrue(existingParent.children.first === insertedEditor)
        XCTAssertTrue(insertedEditor.parent === existingParent)
        XCTAssertTrue(insertedController.attachedNode === insertedEditor)
        XCTAssertFalse(insertedController.wasRevoked)
        XCTAssertNil(departingEditor.parent)
        assertRuntimeClockRoute(departingEditor, through: runtime, isAttached: false)
        XCTAssertNil(runtime.focusedNode)
        XCTAssertTrue(departingController.wasRevokedAtWillDetach)
        XCTAssertTrue(departingController.didDetach)
    }

    func testSingletonTypedMatchingUsesEqualityWithoutHashingKeys() async {
        for newValue in [1, 2] {
            let operations = SingletonIdentityKeyOperations()
            let existing = node(
                identity: identity(SingletonCountedIdentityKey(value: 1, operations: operations)), tag: "same")
            let runtime = runtime(children: [existing])
            let replacement = node(
                identity: identity(SingletonCountedIdentityKey(value: newValue, operations: operations)), tag: "same")

            operations.reset()
            reconcile(runtime.root, with: [replacement])
            let hashCalls = operations.hashCalls
            let equalityCalls = operations.equalityCalls

            // Count only this real reconciliation, excluding setup and assertions.
            // The keys deliberately collide; equality must still decide the claim.
            XCTAssertEqual(hashCalls, 0)
            XCTAssertGreaterThan(equalityCalls, 0)
            XCTAssertTrue(runtime.root.children.first === (newValue == 1 ? existing : replacement))
        }
    }

    func testNonSingletonCardinalityKeepsTheFullTypedClaimingPath() async {
        let cases: [([Int], [Int], [Int])] = [
            ([], [1], [-1]),
            ([1], [], []),
            ([1], [2, 1], [-1, 0]),
            ([1, 2], [2], [1]),
            ([1, 2], [2, 1], [1, 0]),
        ]
        for (oldValues, newValues, expectedClaims) in cases {
            let operations = SingletonIdentityKeyOperations()
            let oldNodes = oldValues.map { value in
                node(identity: identity(SingletonCountedIdentityKey(value: value, operations: operations)), tag: "same")
            }
            let runtime = runtime(children: oldNodes)
            let newNodes = newValues.map { value in
                node(identity: identity(SingletonCountedIdentityKey(value: value, operations: operations)), tag: "same")
            }

            operations.reset()
            reconcile(runtime.root, with: newNodes)
            let hashCalls = operations.hashCalls
            let expectedNodes = expectedClaims.enumerated().map { index, oldIndex in
                oldIndex < 0 ? newNodes[index] : oldNodes[oldIndex]
            }

            XCTAssertEqual(
                runtime.root.children.map(ObjectIdentifier.init), expectedNodes.map(ObjectIdentifier.init))
            XCTAssertEqual(Set(runtime.root.children.map(ObjectIdentifier.init)).count, newNodes.count)
            XCTAssertTrue(runtime.root.children.allSatisfy { $0.parent === runtime.root })
            for child in runtime.root.children {
                assertRuntimeClockRoute(child, through: runtime, isAttached: true)
            }
            if oldValues.count > 1 || newValues.count > 1 {
                XCTAssertGreaterThan(hashCalls, 0, "Non-singleton lists must retain the existing dictionary path")
            }
            for oldNode in oldNodes where !expectedNodes.contains(where: { $0 === oldNode }) {
                XCTAssertNil(oldNode.parent)
                assertRuntimeClockRoute(oldNode, through: runtime, isAttached: false)
            }
        }
    }

    func testSingletonTypedAndUntypedPairsNeverHashOrClaimThroughLegacyTags() async {
        for startsTyped in [false, true] {
            for tag in [String?(nil), "same"] {
                let operations = SingletonIdentityKeyOperations()
                let viewIdentity = identity(SingletonCountedIdentityKey(value: 1, operations: operations))
                let existing = node(identity: startsTyped ? viewIdentity : nil, tag: tag)
                let runtime = runtime(children: [existing])
                let replacement = node(identity: startsTyped ? nil : viewIdentity, tag: tag)

                operations.reset()
                reconcile(runtime.root, with: [replacement])
                let hashCalls = operations.hashCalls
                let equalityCalls = operations.equalityCalls

                XCTAssertEqual(hashCalls, 0)
                XCTAssertEqual(equalityCalls, 0, "A nil typed identity rejects before comparing key payloads")
                XCTAssertTrue(runtime.root.children.first === replacement)
                XCTAssertNil(existing.parent)
                assertRuntimeClockRoute(existing, through: runtime, isAttached: false)
            }
        }
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

@MainActor
private func assertRuntimeClockRoute(
    _ node: ViewNode?, through runtime: RetainedViewRuntime?, isAttached: Bool,
    _ message: String = "", file: StaticString = #filePath, line: UInt = #line
) {
    guard let node, let runtime else {
        XCTFail("The node and its expected runtime must still be alive. \(message)", file: file, line: line)
        return
    }
    let previousClock = runtime.clock
    var clockReads = 0
    runtime.clock = {
        clockReads += 1
        return 0
    }
    defer { runtime.clock = previousClock }

    // Use the existing runtime-backed accessor instead of exposing the private
    // runtime reference. A detached node must not consult its former clock.
    _ = node.animationClockNow
    XCTAssertEqual(clockReads, isAttached ? 1 : 0, message, file: file, line: line)
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

@MainActor
private final class SingletonIdentityTextInputController: RetainedTextInputController {
    private(set) weak var attachedNode: ViewNode?
    private(set) weak var preparedNode: ViewNode?
    private(set) weak var reconciledNode: ViewNode?
    private(set) weak var preparedPrevious: (any RetainedTextInputController)?
    private(set) weak var reconciledPrevious: (any RetainedTextInputController)?
    private(set) var preparationCount = 0
    private(set) var wasPreparedBeforeReconciliation = false
    private(set) var wasRevoked = false
    private(set) var wasRevokedAtWillDetach = false
    private(set) var didDetach = false

    func attach(to node: ViewNode) {
        attachedNode = node
    }

    func prepareForReconciliation(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        preparationCount += 1
        preparedPrevious = previous
        preparedNode = node
    }

    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        wasPreparedBeforeReconciliation = preparationCount > 0 && preparedPrevious === previous && preparedNode === node
        reconciledPrevious = previous
        reconciledNode = node
        attachedNode = node
    }

    func revokeOwnership(from node: ViewNode) {
        // Detached construction nodes have no attached ownership to retire.
        if attachedNode === node { wasRevoked = true }
    }

    func willDetach(from node: ViewNode) {
        wasRevokedAtWillDetach = wasRevoked
    }

    func detach(from node: ViewNode) {
        didDetach = true
        attachedNode = nil
    }
}

// Each counter belongs to one main-actor test and is never shared with another
// test or used by production code. Hashable witnesses stay nonisolated.
private final class SingletonIdentityKeyOperations {
    var hashCalls = 0
    var equalityCalls = 0

    func reset() {
        hashCalls = 0
        equalityCalls = 0
    }
}

private struct SingletonCountedIdentityKey: Hashable {
    let value: Int
    let operations: SingletonIdentityKeyOperations

    static func == (lhs: SingletonCountedIdentityKey, rhs: SingletonCountedIdentityKey) -> Bool {
        lhs.operations.equalityCalls += 1
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        operations.hashCalls += 1
        hasher.combine(0)
    }
}
