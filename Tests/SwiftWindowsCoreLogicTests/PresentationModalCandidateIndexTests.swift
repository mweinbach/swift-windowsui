import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Stored modal lookup only. These tests do not open a window, query UIA,
/// or use elapsed time to decide whether candidate indexing is correct.
@MainActor
final class PresentationModalCandidateIndexTests: XCTestCase {
    func testEmptyCandidatesRefreshForLiveTraitAndChromeWritesWithoutLayout() async {
        let candidate = node()
        let runtime = makeRuntime(children: [candidate])
        defer { retire(runtime) }
        let generation = runtime.currentPrepaintState.generation
        var layouts = 0
        candidate.onLayout = { _ in layouts += 1 }

        XCTAssertNil(runtime.presentationModalSnapshot)
        XCTAssertNil(runtime.presentationModalSnapshot)
        candidate.accessibilityTraits.insert(.isModal)
        XCTAssertTrue(runtime.presentationModalSnapshot === candidate)
        candidate.accessibilityTraits.remove(.isModal)
        XCTAssertNil(runtime.presentationModalSnapshot)

        candidate.presentationChrome.hasBackgroundInteractionOverride = true
        XCTAssertTrue(runtime.presentationModalSnapshot === candidate)
        candidate.presentationChrome.allowsBackgroundInteraction = true
        XCTAssertNil(runtime.presentationModalSnapshot)
        candidate.presentationChrome.allowsBackgroundInteraction = false
        XCTAssertTrue(runtime.presentationModalSnapshot === candidate)
        candidate.presentationChrome.hasBackgroundInteractionOverride = false
        XCTAssertNil(runtime.presentationModalSnapshot)
        XCTAssertNil(runtime.presentationModalSnapshot)
        XCTAssertTrue(runtime.currentPrepaintState.generation === generation)
        XCTAssertEqual(layouts, 0)
    }

    func testPotentialOverridesKeepLiveAncestorAndAvailabilityChecks() async {
        let child = node()
        child.presentationChrome.hasBackgroundInteractionOverride = true
        let parent = node()
        parent.accessibilityTraits = [.isModal]
        parent.addChild(child)
        let runtime = makeRuntime(children: [parent])
        defer { retire(runtime) }

        XCTAssertTrue(runtime.presentationModalSnapshot === parent)
        parent.accessibilityTraits = []
        XCTAssertTrue(runtime.presentationModalSnapshot === child)
        parent.accessibilityTraits = [.isModal]
        XCTAssertTrue(runtime.presentationModalSnapshot === parent)
        child.accessibilityTraits = [.isModal]
        XCTAssertTrue(runtime.presentationModalSnapshot === child)

        // Enabled and accessibility-hidden metadata do not exclude a modal
        // from this input snapshot; physical visibility and deferral do.
        child.accessibilityRespondsToUserInteraction = false
        child.isAccessibilityHidden = true
        XCTAssertTrue(runtime.presentationModalSnapshot === child)
        child.isHidden = true
        XCTAssertTrue(runtime.presentationModalSnapshot === parent)
        child.isHidden = false
        child.isRemovalOverlay = true
        XCTAssertTrue(runtime.presentationModalSnapshot === parent)
        child.isRemovalOverlay = false
        child.isLayoutDeferredByVirtualization = true
        XCTAssertTrue(runtime.presentationModalSnapshot === parent)
        child.isLayoutDeferredByVirtualization = false
        XCTAssertTrue(runtime.presentationModalSnapshot === child)
        parent.isHidden = true
        XCTAssertNil(runtime.presentationModalSnapshot)
        parent.isHidden = false
        XCTAssertTrue(runtime.presentationModalSnapshot === child)
    }

    func testNewPrepaintIdentityReplacesCandidateOffsetsAndKeepsPaintOrder() async {
        let first = node()
        first.accessibilityTraits = [.isModal]
        let ordinary = node()
        let last = node()
        last.accessibilityTraits = [.isModal]
        let runtime = makeRuntime(children: [first, ordinary, last])
        defer { retire(runtime) }
        let originalGeneration = runtime.currentPrepaintState.generation
        XCTAssertTrue(runtime.presentationModalSnapshot === last)

        runtime.root.setChildren([last, first, ordinary])
        XCTAssertTrue(runtime.currentPrepaintState.generation === originalGeneration)
        XCTAssertTrue(runtime.presentationModalSnapshot === last)
        _ = runtime.renderFrame()
        XCTAssertFalse(runtime.currentPrepaintState.generation === originalGeneration)
        XCTAssertTrue(runtime.presentationModalSnapshot === first)

        last.paintsInDeferredPhase = true
        _ = runtime.renderFrame()
        XCTAssertTrue(runtime.presentationModalSnapshot === last)
        runtime.root.removeAllChildren()
        _ = runtime.renderFrame()
        XCTAssertNil(runtime.presentationModalSnapshot)
        runtime.stopRenderLifecycleCallbacks()
        XCTAssertNil(runtime.presentationModalSnapshot)
    }

    func testRuntimeTransferCannotBorrowAnOldEmptyCandidateIndex() async {
        let firstRuntime = makeRuntime(children: [])
        let secondRuntime = makeRuntime(children: [node()])
        defer {
            retire(firstRuntime)
            retire(secondRuntime)
        }
        weak var departed: ViewNode?

        @inline(never)
        func exerciseTransfer() {
            let moving = node()
            departed = moving
            firstRuntime.root.addChild(moving)
            _ = firstRuntime.renderFrame()
            XCTAssertNil(firstRuntime.presentationModalSnapshot)
            XCTAssertNil(secondRuntime.presentationModalSnapshot)

            secondRuntime.root.addChild(moving)
            // Warm the old snapshot while the node is foreign and nonmodal.
            XCTAssertNil(firstRuntime.presentationModalSnapshot)
            moving.accessibilityTraits = [.isModal]
            XCTAssertNil(firstRuntime.presentationModalSnapshot)
            XCTAssertNil(secondRuntime.presentationModalSnapshot)

            firstRuntime.root.addChild(moving)
            // The first prepaint still contains this exact physical node.
            // Its return must see the flag written while the other runtime
            // owned it, without granting the second runtime a missing entry.
            XCTAssertTrue(firstRuntime.presentationModalSnapshot === moving)
            XCTAssertNil(secondRuntime.presentationModalSnapshot)
            moving.removeFromParent()
            _ = firstRuntime.renderFrame()
            _ = secondRuntime.renderFrame()
            XCTAssertNil(firstRuntime.presentationModalSnapshot)
            XCTAssertNil(secondRuntime.presentationModalSnapshot)
        }

        exerciseTransfer()
        XCTAssertNil(departed, "Candidate indices must not retain removed prepaint nodes")
    }

    func testTraitRoleLossInvalidatesBeforeCancellationReentersModalLookup() async throws {
        let source = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 30), isFocusable: true,
            accessibilityTraits: .isSelectable)
        source.interceptsVerticalArrowKeys = true
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 80), scrollAxis: .vertical,
            children: [source])
        let runtime = makeRuntime(children: [scroll])
        defer { retire(runtime) }
        let scope = RetainedListNavigationOwner(runtime: runtime)
        scope.install(on: scroll)
        let sourceOwner = scope.makeRowOwner(on: source)
        let receipt = try XCTUnwrap(scope.prepareAction(from: sourceOwner))
        let generation = runtime.currentPrepaintState.generation
        var cancellations = 0
        var deliveries = 0
        var observedNewModal = false
        var observedRevocation = false
        XCTAssertTrue(
            receipt.schedulePreparedNavigationReplay(
                afterLayout: true,
                perform: { deliveries += 1 },
                onCancel: {
                    cancellations += 1
                    observedNewModal = runtime.presentationModalSnapshot === source
                    observedRevocation = !receipt.permitsContinuation
                }))
        XCTAssertNil(runtime.presentationModalSnapshot)
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(deliveries, 0)

        // This one write both adds modal intent and removes the row role.
        // Cancellation can query before the setter reaches paint invalidation.
        source.accessibilityTraits = [.isModal]

        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(deliveries, 0)
        XCTAssertTrue(observedNewModal)
        XCTAssertTrue(observedRevocation)
        XCTAssertTrue(runtime.currentPrepaintState.generation === generation)
        XCTAssertTrue(runtime.presentationModalSnapshot === source)
    }

    func testSelectedReplacementAndLayoutReentryKeepTheOriginalSnapshotPolicy() async {
        let original = node()
        original.accessibilityTraits = [.isModal]
        let boundary = ViewNode.selectedContentBoundary(role: .viewThatFits, child: original)
        let runtime = makeRuntime(children: [boundary])
        defer { retire(runtime) }
        XCTAssertTrue(runtime.presentationModalSnapshot === original)

        let replacement = node()
        replacement.accessibilityTraits = [.isModal]
        boundary.setChildren([replacement])
        XCTAssertNil(runtime.presentationModalSnapshot)
        _ = runtime.renderFrame()
        XCTAssertTrue(runtime.presentationModalSnapshot === replacement)

        var snapshotChecks: [Bool] = []
        var actionAdmissions: [Bool] = []
        replacement.onLayout = { [weak runtime, weak replacement] _ in
            guard let runtime, let replacement else { return }
            replacement.accessibilityTraits = []
            snapshotChecks.append(runtime.presentationModalSnapshot == nil)
            replacement.accessibilityTraits = [.isModal]
            snapshotChecks.append(runtime.presentationModalSnapshot === replacement)
            actionAdmissions.append(runtime.presentationActionsAreAvailable)
        }
        replacement.frame.size.width += 1
        _ = runtime.renderFrame()
        XCTAssertFalse(snapshotChecks.isEmpty)
        XCTAssertTrue(snapshotChecks.allSatisfy { $0 })
        XCTAssertFalse(actionAdmissions.isEmpty)
        XCTAssertTrue(actionAdmissions.allSatisfy { !$0 })
    }

    private func node() -> ViewNode {
        ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 30))
    }

    private func makeRuntime(children: [ViewNode]) -> RetainedViewRuntime {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 80), children: children)
        let runtime = RetainedViewRuntime(root: root)
        runtime.setRootSize(IntSize(width: 120, height: 80))
        _ = runtime.renderFrame()
        return runtime
    }

    private func retire(_ runtime: RetainedViewRuntime) {
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
    }
}
