import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
final class TransitionConstructionOwnershipTests: XCTestCase {
    func testConstructionTransferDoesNotCreateAnOverlayAndLiveRemovalStillFades() async throws {
        for usesScene in [false, true] {
            let clock = RuntimeTestClock()
            clock.now = 100
            let leaf = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20))
            let candidate = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 30), backgroundColor: .white,
                transition: RetainedTransition(kind: .opacity), children: [leaf])
            let stagingParent = ViewNode(children: [candidate])
            let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 60)))
            runtime.clock = { clock.now }
            var events: [String] = []
            var dismantles = 0
            candidate.onAppear = { events.append("parent.appear") }
            candidate.onDisappear = { events.append("parent.disappear") }
            candidate.onDismantlePlatformView = { _ in dismantles += 1 }
            leaf.onAppear = { events.append("leaf.appear") }
            leaf.onDisappear = { events.append("leaf.disappear") }

            runtime.root.addChild(candidate)

            XCTAssertTrue(stagingParent.children.isEmpty)
            XCTAssertTrue(candidate.parent === runtime.root)
            XCTAssertFalse(candidate.isRemovalOverlay, "A staging parent cannot own a removal overlay")
            XCTAssertTrue(candidate.animationStates.isEmpty, "Adoption must not seed a removal tween")
            XCTAssertEqual(candidate.opacity, 1)
            XCTAssertTrue(runtime.transitionOverlays.isEmpty)
            XCTAssertEqual(dismantles, 1, "The ownership guard must not bypass existing dismantle handling")
            XCTAssertTrue(events.isEmpty)
            render(runtime, usesScene: usesScene, at: clock.now)
            XCTAssertEqual(events, ["parent.appear", "leaf.appear"])
            XCTAssertTrue(candidate.hasAppeared)
            XCTAssertTrue(leaf.hasAppeared)

            candidate.removeFromParent()

            XCTAssertNil(candidate.parent)
            XCTAssertTrue(candidate.isRemovalOverlay)
            XCTAssertEqual(runtime.transitionOverlays.count, 1)
            XCTAssertTrue(runtime.transitionOverlays.first === candidate)
            XCTAssertEqual(dismantles, 2)
            XCTAssertEqual(events, ["parent.appear", "leaf.appear"])
            let fade = try XCTUnwrap(candidate.animationStates[.opacity])
            clock.now = fade.startTime + fade.duration * 0.5
            _ = runtime.tickAnimations(at: clock.now)
            render(runtime, usesScene: usesScene, at: clock.now)
            XCTAssertGreaterThan(candidate.opacity, 0)
            XCTAssertLessThan(candidate.opacity, 1)
            XCTAssertEqual(events, ["parent.appear", "leaf.appear"])

            clock.now = fade.startTime + fade.duration + 0.01
            _ = runtime.tickAnimations(at: clock.now)
            render(runtime, usesScene: usesScene, at: clock.now)
            XCTAssertTrue(runtime.transitionOverlays.isEmpty)
            XCTAssertFalse(candidate.isRemovalOverlay)
            XCTAssertEqual(events, ["parent.appear", "leaf.appear", "parent.disappear", "leaf.disappear"])
        }
    }

    func testUnattachedRemoveAllChildrenDoesNotCreateOrphanTransitions() async {
        for usesScene in [false, true] {
            let first = ViewNode(
                frame: Rect(x: 0, y: 0, width: 20, height: 20), backgroundColor: .white,
                transition: RetainedTransition(kind: .opacity))
            let second = ViewNode(
                frame: Rect(x: 30, y: 0, width: 20, height: 20), backgroundColor: .white,
                transition: RetainedTransition(kind: .opacity))
            let stagingParent = ViewNode(children: [first, second])
            var events: [String] = []
            first.onAppear = { events.append("first.appear") }
            first.onDisappear = { events.append("first.disappear") }
            second.onAppear = { events.append("second.appear") }
            second.onDisappear = { events.append("second.disappear") }

            stagingParent.removeAllChildren()

            XCTAssertTrue(stagingParent.children.isEmpty)
            for child in [first, second] {
                XCTAssertNil(child.parent)
                XCTAssertFalse(child.isRemovalOverlay)
                XCTAssertTrue(child.animationStates.isEmpty)
                XCTAssertEqual(child.opacity, 1)
                XCTAssertFalse(child.hasAppeared)
            }
            XCTAssertTrue(events.isEmpty)

            let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 60)))
            runtime.root.addChild(first)
            runtime.root.addChild(second)
            render(runtime, usesScene: usesScene, at: 0)

            XCTAssertTrue(runtime.transitionOverlays.isEmpty)
            XCTAssertTrue(first.hasAppeared)
            XCTAssertTrue(second.hasAppeared)
            XCTAssertEqual(events, ["first.appear", "second.appear"])
            render(runtime, usesScene: !usesScene, at: 0)
            XCTAssertEqual(events, ["first.appear", "second.appear"])
        }
    }

    private func render(_ runtime: RetainedViewRuntime, usesScene: Bool, at timestamp: Double) {
        if usesScene { _ = runtime.renderScene(at: timestamp) } else { _ = runtime.renderFrame(at: timestamp) }
    }
}
