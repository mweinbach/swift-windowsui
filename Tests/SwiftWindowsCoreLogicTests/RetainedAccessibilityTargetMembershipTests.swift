import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Physical attachment checks only. Wide-tree coverage is not a timing benchmark.
@MainActor
final class RetainedAccessibilityTargetMembershipTests: XCTestCase {
    func testUnchangedWideSiblingTargetsRemainCurrentWithoutCallbacks() async throws {
        let leaves = (0..<512).map { _ in ViewNode() }
        let parent = ViewNode(children: leaves)
        let neighbors = (0..<511).map { _ in ViewNode() }
        let root = ViewNode(children: neighbors + [parent])
        let runtime = RetainedViewRuntime(root: root)
        let nodes = [root, parent, leaves[0], leaves[255], leaves[511]]
        var callbacks = 0
        runtime.clock = {
            callbacks += 1
            return 0
        }
        for node in nodes {
            node.onLayout = { _ in callbacks += 1 }
            node.onActivate = { callbacks += 1 }
        }
        let targets = try nodes.map { try XCTUnwrap(runtime.accessibilityTarget(for: $0)) }
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }

        for _ in 0..<64 {
            for target in targets {
                XCTAssertTrue(runtime.isAccessibilityTargetCurrent(target, during: mutation))
            }
        }

        XCTAssertEqual(root.children.count, 512)
        XCTAssertEqual(parent.children.count, 512)
        XCTAssertTrue(runtime.isAccessibilityMutationCurrent(mutation))
        XCTAssertEqual(callbacks, 0)
    }

    func testSiblingAndAncestorReorderPreservesOriginalTarget() async throws {
        let target = ViewNode()
        let first = ViewNode()
        let last = ViewNode()
        let parent = ViewNode(children: [first, target, last])
        let before = ViewNode()
        let after = ViewNode()
        let root = ViewNode(children: [before, parent, after])
        let runtime = RetainedViewRuntime(root: root)
        let original = try XCTUnwrap(runtime.accessibilityTarget(for: target))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }

        XCTAssertTrue(parent.setChildren([target, last, first]).completed)
        XCTAssertTrue(root.setChildren([parent, after, before]).completed)

        XCTAssertTrue(parent.children[0] === target)
        XCTAssertTrue(root.children[0] === parent)
        XCTAssertTrue(runtime.isAccessibilityMutationCurrent(mutation))
        XCTAssertTrue(runtime.isAccessibilityTargetCurrent(original, during: mutation))
    }

    func testSurvivingTargetRemainsCurrentWhenOldIndexIsOutOfBounds() async throws {
        let children = (0..<64).map { _ in ViewNode() }
        let target = children[63]
        let root = ViewNode(children: children)
        let runtime = RetainedViewRuntime(root: root)
        let original = try XCTUnwrap(runtime.accessibilityTarget(for: target))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }

        XCTAssertTrue(root.setChildren([target]).completed)

        XCTAssertEqual(root.children.count, 1)
        XCTAssertTrue(root.children[0] === target)
        XCTAssertTrue(target.parent === root)
        XCTAssertTrue(runtime.isAccessibilityMutationCurrent(mutation))
        XCTAssertTrue(runtime.isAccessibilityTargetCurrent(original, during: mutation))
    }

    func testRemovedTargetCannotBorrowSiblingNowAtCapturedIndex() async throws {
        let target = ViewNode()
        let sibling = ViewNode()
        let root = ViewNode(children: [target, sibling])
        let runtime = RetainedViewRuntime(root: root)
        let original = try XCTUnwrap(runtime.accessibilityTarget(for: target))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }

        root.removeChild(target)

        XCTAssertTrue(root.children[0] === sibling)
        XCTAssertNil(target.parent)
        XCTAssertNil(runtime.accessibilityTarget(for: target))
        XCTAssertTrue(runtime.isAccessibilityMutationCurrent(mutation))
        XCTAssertFalse(runtime.isAccessibilityTargetCurrent(original, during: mutation))
        let fresh = try XCTUnwrap(runtime.accessibilityTarget(for: sibling))
        XCTAssertTrue(runtime.isAccessibilityTargetCurrent(fresh, during: mutation))
    }

    func testReplacementAtCapturedIndexCannotReviveOriginalTarget() async throws {
        let target = ViewNode()
        target.text = "same label"
        let root = ViewNode(children: [target])
        let runtime = RetainedViewRuntime(root: root)
        let original = try XCTUnwrap(runtime.accessibilityTarget(for: target))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        let replacement = ViewNode()
        replacement.text = target.text

        root.replaceChild(at: 0, with: replacement)

        XCTAssertTrue(root.children[0] === replacement)
        XCTAssertNil(target.parent)
        XCTAssertNil(runtime.accessibilityTarget(for: target))
        XCTAssertTrue(runtime.isAccessibilityMutationCurrent(mutation))
        XCTAssertFalse(runtime.isAccessibilityTargetCurrent(original, during: mutation))
        let fresh = try XCTUnwrap(runtime.accessibilityTarget(for: replacement))
        XCTAssertTrue(runtime.isAccessibilityTargetCurrent(fresh, during: mutation))
    }

    func testDetachAndReattachAtSameIndexDoesNotRestoreAttachmentIdentity() async throws {
        let target = ViewNode()
        let root = ViewNode(children: [target])
        let runtime = RetainedViewRuntime(root: root)
        let original = try XCTUnwrap(runtime.accessibilityTarget(for: target))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }

        root.removeChild(target)
        root.addChild(target)

        XCTAssertTrue(root.children[0] === target)
        XCTAssertTrue(target.parent === root)
        XCTAssertTrue(runtime.isAccessibilityMutationCurrent(mutation))
        XCTAssertFalse(runtime.isAccessibilityTargetCurrent(original, during: mutation))
        let fresh = try XCTUnwrap(runtime.accessibilityTarget(for: target))
        XCTAssertTrue(runtime.isAccessibilityTargetCurrent(fresh, during: mutation))
        XCTAssertFalse(runtime.isAccessibilityTargetCurrent(original, during: mutation))
    }

    func testAncestorDetachAndReattachInvalidatesUnmovedDescendantTarget() async throws {
        let target = ViewNode()
        let parent = ViewNode(children: [target])
        let root = ViewNode(children: [parent])
        let runtime = RetainedViewRuntime(root: root)
        let original = try XCTUnwrap(runtime.accessibilityTarget(for: target))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }

        root.removeChild(parent)
        root.addChild(parent)

        XCTAssertTrue(root.children[0] === parent)
        XCTAssertTrue(parent.children[0] === target)
        XCTAssertTrue(target.parent === parent)
        XCTAssertTrue(runtime.isAccessibilityMutationCurrent(mutation))
        XCTAssertFalse(runtime.isAccessibilityTargetCurrent(original, during: mutation))
        let fresh = try XCTUnwrap(runtime.accessibilityTarget(for: target))
        XCTAssertTrue(runtime.isAccessibilityTargetCurrent(fresh, during: mutation))
    }

    func testReparentAndReturnCannotReuseOriginalPath() async throws {
        let target = ViewNode()
        let firstParent = ViewNode(children: [target])
        let secondParent = ViewNode()
        let root = ViewNode(children: [firstParent, secondParent])
        let runtime = RetainedViewRuntime(root: root)
        let original = try XCTUnwrap(runtime.accessibilityTarget(for: target))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }

        secondParent.addChild(target)

        XCTAssertTrue(target.parent === secondParent)
        XCTAssertTrue(secondParent.children[0] === target)
        XCTAssertTrue(runtime.isAccessibilityMutationCurrent(mutation))
        XCTAssertFalse(runtime.isAccessibilityTargetCurrent(original, during: mutation))
        let intermediate = try XCTUnwrap(runtime.accessibilityTarget(for: target))
        XCTAssertTrue(runtime.isAccessibilityTargetCurrent(intermediate, during: mutation))

        firstParent.addChild(target)

        XCTAssertTrue(target.parent === firstParent)
        XCTAssertTrue(firstParent.children[0] === target)
        XCTAssertTrue(runtime.isAccessibilityMutationCurrent(mutation))
        XCTAssertFalse(runtime.isAccessibilityTargetCurrent(original, during: mutation))
        XCTAssertFalse(runtime.isAccessibilityTargetCurrent(intermediate, during: mutation))
        let fresh = try XCTUnwrap(runtime.accessibilityTarget(for: target))
        XCTAssertTrue(runtime.isAccessibilityTargetCurrent(fresh, during: mutation))
    }

    func testDifferentRuntimeAndRootCannotAcceptOriginalPath() async throws {
        let target = ViewNode()
        let firstRoot = ViewNode(children: [target])
        let firstRuntime = RetainedViewRuntime(root: firstRoot)
        let secondRoot = ViewNode()
        let secondRuntime = RetainedViewRuntime(root: secondRoot)
        let original = try XCTUnwrap(firstRuntime.accessibilityTarget(for: target))
        let firstMutation = try XCTUnwrap(firstRuntime.beginAccessibilityMutation())
        defer { firstRuntime.endAccessibilityMutation(firstMutation) }
        let secondMutation = try XCTUnwrap(secondRuntime.beginAccessibilityMutation())
        defer { secondRuntime.endAccessibilityMutation(secondMutation) }
        XCTAssertFalse(secondRuntime.isAccessibilityTargetCurrent(original, during: secondMutation))

        secondRoot.addChild(target)

        XCTAssertTrue(target.parent === secondRoot)
        XCTAssertTrue(secondRoot.children[0] === target)
        XCTAssertNil(firstRuntime.accessibilityTarget(for: target))
        XCTAssertTrue(firstRuntime.isAccessibilityMutationCurrent(firstMutation))
        XCTAssertTrue(secondRuntime.isAccessibilityMutationCurrent(secondMutation))
        XCTAssertFalse(firstRuntime.isAccessibilityTargetCurrent(original, during: firstMutation))
        XCTAssertFalse(secondRuntime.isAccessibilityTargetCurrent(original, during: secondMutation))
        let fresh = try XCTUnwrap(secondRuntime.accessibilityTarget(for: target))
        XCTAssertTrue(secondRuntime.isAccessibilityTargetCurrent(fresh, during: secondMutation))
    }

    func testCapturedHintsDoNotKeepRuntimeOrNodesAlive() async throws {
        var runtime: RetainedViewRuntime? = RetainedViewRuntime(root: ViewNode(children: [ViewNode()]))
        weak var releasedRuntime = runtime
        weak var releasedRoot = runtime?.root
        weak var releasedChild = runtime?.root.children.first
        let original = try XCTUnwrap(
            runtime?.accessibilityTarget(for: try XCTUnwrap(runtime?.root.children.first)))

        runtime = nil

        withExtendedLifetime(original) {
            XCTAssertNil(releasedRuntime)
            XCTAssertNil(releasedRoot)
            XCTAssertNil(releasedChild)
            XCTAssertNil(original.node)
        }
    }
}
