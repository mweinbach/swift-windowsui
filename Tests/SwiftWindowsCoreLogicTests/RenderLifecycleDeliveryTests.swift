import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RenderLifecycleDeliveryTests: XCTestCase {
    func testLayoutQueriesDoNotAppearAndRawSceneSnapshotDeliversOnce() async throws {
        let child = ViewNode(frame: Rect(x: 8, y: 6, width: 20, height: 20), backgroundColor: .white)
        let runtime = makeRuntime(children: [child])
        var events: [String] = []
        child.onAppear = { events.append("appear") }
        child.onDisappear = { events.append("disappear") }

        XCTAssertEqual(runtime.resolvedLayoutFrame(of: child), Rect(x: 8, y: 6, width: 20, height: 20))
        runtime.pointerMoved(to: Point(x: 10, y: 10))
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(child.hasAppeared)

        let bitmap = try ViewSnapshot.rasterize(runtime: runtime, size: runtime.root.frame.size)

        XCTAssertEqual(events, ["appear"])
        XCTAssertEqual(bitmap.pixelColor(atX: 12, y: 12), .white)
        _ = runtime.renderScene()
        _ = runtime.renderFrame()
        _ = runtime.renderScene()
        XCTAssertEqual(events, ["appear"])
        child.removeFromParent()
        XCTAssertEqual(events, ["appear", "disappear"])
    }

    func testSizeChangesUsePresentedLayoutCoordinatesOnceAcrossRenderPaths() async {
        let child = ViewNode(frame: Rect(x: 5, y: 15, width: 20, height: 12), backgroundColor: .white)
        let content = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 200), children: [child])
        let scroller = ViewNode(
            frame: Rect(x: 20, y: 30, width: 100, height: 60), clipsToBounds: true,
            scrollAxis: .vertical, scrollOffset: 10, children: [content])
        scroller.transform = .translation(x: 8, y: 3)
        let runtime = makeRuntime(children: [scroller])
        var appearances = 0
        var frames: [Rect] = []
        child.onAppear = { appearances += 1 }
        child.onSizeChange = { frames.append($0) }
        _ = runtime.renderScene()
        XCTAssertEqual(appearances, 1)
        XCTAssertTrue(frames.isEmpty)

        child.frame = Rect(x: 5, y: 18, width: 24, height: 12)
        _ = runtime.renderScene()

        // Bounds retain the preexisting layout-space contract. Scrolling is
        // a presented offset; the paint transform is only used for culling.
        XCTAssertEqual(frames, [Rect(x: 25, y: 38, width: 24, height: 12)])
        _ = runtime.renderFrame()
        _ = runtime.renderScene()
        XCTAssertEqual(appearances, 1)
        XCTAssertEqual(frames.count, 1)
    }

    func testHiddenClippedOpacityAndZeroExtentVisibilityRetainTheirOrdering() async {
        let hiddenChild = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
        let hidden = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20), children: [hiddenChild])
        hidden.isHidden = true
        let clippedChild = ViewNode(frame: Rect(x: 150, y: 0, width: 10, height: 10))
        let transparentChild = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
        let transparent = ViewNode(
            frame: Rect(x: 0, y: 20, width: 20, height: 20), children: [transparentChild])
        transparent.opacity = 0
        let overflow = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
        let zeroExtent = ViewNode(frame: Rect(x: 30, y: 20, width: 0, height: 0), children: [overflow])
        zeroExtent.layoutConstraints = LayoutConstraints(maxWidth: 0, maxHeight: 0)
        let zeroClipChild = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
        let zeroClip = ViewNode(
            frame: Rect(x: 50, y: 20, width: 0, height: 0), clipsToBounds: true, children: [zeroClipChild])
        zeroClip.layoutConstraints = LayoutConstraints(maxWidth: 0, maxHeight: 0)
        let viewport = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 80), clipsToBounds: true,
            children: [hidden, clippedChild, transparent, zeroExtent, zeroClip])
        let runtime = makeRuntime(children: [viewport])

        _ = runtime.renderScene()

        XCTAssertFalse(hidden.hasAppeared)
        XCTAssertFalse(hiddenChild.hasAppeared)
        XCTAssertFalse(clippedChild.hasAppeared)
        XCTAssertTrue(transparent.hasAppeared)
        XCTAssertFalse(transparentChild.hasAppeared)
        XCTAssertEqual(zeroExtent.resolvedFrame.size, .zero)
        XCTAssertTrue(zeroExtent.hasAppeared)
        XCTAssertTrue(overflow.hasAppeared)
        XCTAssertEqual(zeroClip.resolvedFrame.size, .zero)
        XCTAssertTrue(zeroClip.hasAppeared)
        XCTAssertFalse(zeroClipChild.hasAppeared)

        hidden.isHidden = false
        transparent.opacity = 1
        _ = runtime.renderScene()
        XCTAssertTrue(hidden.hasAppeared)
        XCTAssertTrue(hiddenChild.hasAppeared)
        XCTAssertTrue(transparentChild.hasAppeared)
    }

    func testVirtualizedRowsAppearOnlyWhenTheirViewportCanReachThem() async {
        let rows = (0..<40).map { _ in
            ViewNode(backgroundColor: .white, preferredSize: Size(width: 100, height: 20))
        }
        let scroller = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 40), clipsToBounds: true,
            layoutMode: .lazyStack(.vertical(spacing: 0)), scrollAxis: .vertical, children: rows)
        let runtime = makeRuntime(children: [scroller])
        var appearances = 0
        rows[20].onAppear = { appearances += 1 }
        _ = runtime.renderScene()
        XCTAssertTrue(rows[0].hasAppeared)
        XCTAssertTrue(rows[20].isLayoutDeferredByVirtualization)
        XCTAssertFalse(rows[20].hasAppeared)
        XCTAssertEqual(appearances, 0)

        scroller.scrollOffset = 400
        _ = runtime.renderScene()

        XCTAssertFalse(rows[20].isLayoutDeferredByVirtualization)
        XCTAssertTrue(rows[20].hasAppeared)
        XCTAssertEqual(appearances, 1)
        scroller.scrollOffset = 0
        _ = runtime.renderScene()
        scroller.scrollOffset = 400
        _ = runtime.renderScene()
        XCTAssertEqual(appearances, 1, "Viewport culling alone does not remove a retained row")
    }

    func testDeferredAndIsolatedScenePaintingDoesNotRepeatLifecycle() async {
        let ordinary = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20), backgroundColor: .white)
        let deferred = ViewNode(frame: Rect(x: 30, y: 0, width: 20, height: 20), backgroundColor: .white)
        deferred.paintsInDeferredPhase = true
        let isolated = ViewNode(
            frame: Rect(x: 0, y: 40, width: 70, height: 30), children: [ordinary, deferred])
        isolated.contentBlurRadius = 1
        isolated.colorEffects = [.colorInvert]
        let runtime = makeRuntime(children: [isolated])
        var events: [String] = []
        ordinary.onAppear = { events.append("ordinary") }
        deferred.onAppear = { events.append("deferred") }

        _ = runtime.renderScene()
        XCTAssertEqual(events, ["ordinary", "deferred"])
        ordinary.backgroundColor = .black
        _ = runtime.renderScene()
        _ = runtime.renderFrame()
        _ = runtime.renderScene()
        XCTAssertEqual(events, ["ordinary", "deferred"])
    }

    func testRemovalOverlayWaitsForItsTransitionWithoutAppearingAgain() async {
        let child = ViewNode(
            frame: Rect(x: 0, y: 0, width: 30, height: 20), backgroundColor: .white,
            transition: RetainedTransition(kind: .opacity))
        let runtime = makeRuntime(children: [child])
        let clock = RuntimeTestClock()
        clock.now = 50
        runtime.clock = { clock.now }
        var events: [String] = []
        child.onAppear = { events.append("appear") }
        child.onDisappear = { events.append("disappear") }
        _ = runtime.renderScene(at: clock.now)

        child.removeFromParent()
        _ = runtime.renderScene(at: clock.now)

        XCTAssertEqual(events, ["appear"])
        XCTAssertEqual(runtime.transitionOverlays.count, 1)
        clock.now += 10
        _ = runtime.tickAnimations(at: clock.now)
        _ = runtime.renderScene(at: clock.now)
        XCTAssertEqual(events, ["appear", "disappear"])
        XCTAssertTrue(runtime.transitionOverlays.isEmpty)
    }

    func testSelfRemovalStopsTheRemainingAppearanceCallbackAndDefersLaterCandidates() async {
        let first = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20))
        let later = ViewNode(frame: Rect(x: 30, y: 0, width: 20, height: 20))
        let runtime = makeRuntime(children: [first, later])
        var events: [String] = []
        first.onAppear = { [weak first] in
            events.append("first.appear")
            first?.removeFromParent()
        }
        first.onAppearWithNode = { _ in events.append("stale.node.appear") }
        first.onDisappear = { events.append("first.disappear") }
        later.onAppear = { events.append("later.appear") }

        _ = runtime.renderScene()

        XCTAssertEqual(events, ["first.appear", "first.disappear"])
        XCTAssertTrue(runtime.isDirty)
        XCTAssertFalse(later.hasAppeared)
        _ = runtime.renderScene()
        XCTAssertEqual(events, ["first.appear", "first.disappear", "later.appear"])
        XCTAssertFalse(runtime.isDirty)
    }

    func testSceneRenderedInsideBuildCompletionLeavesAppearanceForTheNextNormalRender() async {
        let runtime = makeRuntime(children: [])
        let host = ComponentHost(runtime: runtime)
        host.buildLifecycle = RenderLifecycleBuildOwner()
        let child = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20), backgroundColor: .white)
        var appearances = 0
        var guardedRenders = 0
        child.onAppear = { appearances += 1 }
        host.onReloadCompleted = { [weak host, weak runtime] in
            guard let host, let runtime else { return }
            XCTAssertTrue(host.isBuilding)
            _ = runtime.renderScene()
            guardedRenders += 1
            XCTAssertFalse(child.hasAppeared)
        }
        defer { host.onReloadCompleted = nil }

        host.setContent(Component { _ in child })

        XCTAssertEqual(guardedRenders, 1)
        XCTAssertEqual(appearances, 0)
        XCTAssertTrue(runtime.isDirty, "A cached first scene cannot consume the pending lifecycle stage")
        _ = runtime.renderScene()
        XCTAssertEqual(appearances, 1)
        XCTAssertFalse(runtime.isDirty)
        _ = runtime.renderFrame()
        XCTAssertEqual(appearances, 1)
    }

    func testRebuildingTheSamePendingNodeDefersAppearanceUntilItsNewFrameIsResolved() async throws {
        let runtime = makeRuntime(children: [])
        let host = ComponentHost(runtime: runtime)
        var didRebuild = false
        var width: Double = 20
        var frames: [Rect] = []
        host.setComponents { [weak host] in
            [
                Component { _ in
                    let trigger = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20))
                    trigger.nodeTag = "trigger"
                    trigger.onAppear = { [weak host] in
                        guard !didRebuild else { return }
                        didRebuild = true
                        width = 50
                        host?.reload()
                    }
                    let pending = ViewNode(frame: Rect(x: 30, y: 0, width: width, height: 20))
                    pending.nodeTag = "pending"
                    pending.onAppearWithNode = { frames.append($0.resolvedFrame) }
                    return ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 40), children: [trigger, pending])
                }
            ]
        }
        let pending = try XCTUnwrap(runtime.root.children.first?.children.last)

        _ = runtime.renderScene()

        XCTAssertTrue(didRebuild)
        XCTAssertTrue(runtime.root.children.first?.children.last === pending)
        XCTAssertTrue(frames.isEmpty)
        XCTAssertFalse(pending.hasAppeared)
        XCTAssertTrue(runtime.isDirty)
        _ = runtime.renderScene()
        XCTAssertEqual(frames, [Rect(x: 30, y: 0, width: 50, height: 20)])
        XCTAssertTrue(pending.hasAppeared)
        XCTAssertFalse(runtime.isDirty)
    }

    func testNestedSceneSizeCallbackCommitsItsFrameBeforeReentry() async {
        let child = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20), backgroundColor: .black)
        let runtime = makeRuntime(children: [child])
        var frames: [Rect] = []
        child.onSizeChange = { [weak runtime, weak child] frame in
            frames.append(frame)
            _ = runtime?.renderFrame()
            child?.backgroundColor = .white
        }
        _ = runtime.renderScene()
        child.frame = Rect(x: 10, y: 0, width: 30, height: 20)

        _ = runtime.renderScene()

        XCTAssertEqual(frames, [child.frame])
        XCTAssertTrue(runtime.isDirty)
        let settled = runtime.renderScene()
        XCTAssertEqual(frames.count, 1)
        XCTAssertFalse(runtime.isDirty)
        XCTAssertTrue(settled.layers.flatMap(\.quads).contains { $0.startR == 1 && $0.startG == 1 && $0.startB == 1 })
    }

    func testCurrentAppearanceFinishesWithTheLatestCallbackAfterItsRebuildResolves() async throws {
        let runtime = makeRuntime(children: [])
        let host = ComponentHost(runtime: runtime)
        var version = 0
        var appearances: [Int] = []
        var nodeCallbackVersions: [Int] = []
        var frames: [Rect] = []
        host.setComponents { [weak host] in
            let builtVersion = version
            return [
                Component { _ in
                    let node = ViewNode(frame: Rect(x: 0, y: 0, width: builtVersion == 0 ? 20 : 50, height: 20))
                    node.nodeTag = "same-appearance"
                    node.onAppear = { [weak host] in
                        appearances.append(builtVersion)
                        if version == 0 {
                            version = 1
                            host?.reload()
                        }
                    }
                    node.onAppearWithNode = {
                        nodeCallbackVersions.append(builtVersion)
                        frames.append($0.resolvedFrame)
                    }
                    return node
                }
            ]
        }
        let node = try XCTUnwrap(runtime.root.children.first)

        _ = runtime.renderScene()

        XCTAssertTrue(runtime.root.children.first === node)
        XCTAssertEqual(appearances, [0])
        XCTAssertTrue(nodeCallbackVersions.isEmpty)
        XCTAssertTrue(node.hasPendingAppearanceCallbacks)
        XCTAssertTrue(runtime.isDirty)
        _ = runtime.renderScene()
        XCTAssertEqual(appearances, [0])
        XCTAssertEqual(nodeCallbackVersions, [1])
        XCTAssertEqual(frames, [Rect(x: 0, y: 0, width: 50, height: 20)])
        XCTAssertFalse(node.hasPendingAppearanceCallbacks)
        _ = runtime.renderFrame()
        XCTAssertEqual(nodeCallbackVersions, [1])
    }

    func testPaintOnlyAppearanceMutationStillCompletesItsNodeCallback() async {
        let child = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20), backgroundColor: .black)
        let runtime = makeRuntime(children: [child])
        var appearances = 0
        var nodeCallbacks = 0
        child.onAppear = { [weak child] in
            appearances += 1
            child?.backgroundColor = .white
        }
        child.onAppearWithNode = { _ in nodeCallbacks += 1 }

        _ = runtime.renderScene()

        XCTAssertEqual(appearances, 1)
        XCTAssertEqual(nodeCallbacks, 0)
        XCTAssertTrue(child.hasPendingAppearanceCallbacks)
        XCTAssertTrue(runtime.isDirty)
        _ = runtime.renderFrame()
        XCTAssertEqual(appearances, 1)
        XCTAssertEqual(nodeCallbacks, 1)
        XCTAssertFalse(child.hasPendingAppearanceCallbacks)
        XCTAssertFalse(runtime.isDirty)
        _ = runtime.renderScene()
        XCTAssertEqual(nodeCallbacks, 1)
    }

    func testRemovingAndReinsertingTheSameNodeCanLaunchItsTaskAgain() async {
        let child = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20))
        let runtime = makeRuntime(children: [child])
        let probe = RenderLifecycleTaskProbe()
        let firstStart = expectNextTaskStart(on: probe)
        child.onAppearWithNode = { node in
            node.launchLifecycleTask(
                ViewLifecycleTaskLaunch(key: "reinsert", priority: .userInitiated) {
                    await probe.recordStart()
                })
        }

        _ = runtime.renderScene()
        await fulfillment(of: [firstStart], timeout: 5)
        XCTAssertEqual(probe.starts, 1)
        child.removeFromParent()
        XCTAssertFalse(child.hasAppeared)
        let secondStart = expectNextTaskStart(on: probe)
        runtime.root.addChild(child)
        _ = runtime.renderScene()
        await fulfillment(of: [secondStart], timeout: 5)

        XCTAssertTrue(child.hasAppeared)
        XCTAssertEqual(probe.starts, 2, "An ordinary removal must not permanently retire task ownership")
        _ = runtime.renderFrame()
        for _ in 0..<4 { await Task.yield() }
        XCTAssertEqual(probe.starts, 2)
        child.removeFromParent()
    }

    func testPendingOnlyTaskRetainsTheLatestBuildThroughAppearanceDeferral() async throws {
        let runtime = makeRuntime(children: [])
        let host = ComponentHost(runtime: runtime)
        let probe = RenderLifecycleTaskProbe()
        var version = 0
        host.setComponents { [weak host] in
            let builtVersion = version
            return [
                Component { _ in
                    let node = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20))
                    node.nodeTag = "pending-only"
                    node.onAppear = { [weak host] in
                        if version == 0 {
                            version = 1
                            host?.reload()
                        }
                    }
                    node.pendingLifecycleTaskLaunches = [
                        ViewLifecycleTaskLaunch(key: "pending-only", priority: .userInitiated) {
                            await probe.recordStart(version: builtVersion)
                        }
                    ]
                    return node
                }
            ]
        }
        let node = try XCTUnwrap(runtime.root.children.first)

        _ = runtime.renderScene()

        XCTAssertTrue(runtime.root.children.first === node)
        XCTAssertTrue(node.hasPendingAppearanceCallbacks)
        XCTAssertNil(node.onAppearWithNode)
        for _ in 0..<4 { await Task.yield() }
        XCTAssertEqual(probe.starts, 0)
        let taskStart = expectNextTaskStart(on: probe)
        _ = runtime.renderScene()
        await fulfillment(of: [taskStart], timeout: 5)
        XCTAssertEqual(probe.versions, [1])
        XCTAssertEqual(probe.starts, 1)
        XCTAssertFalse(node.hasPendingAppearanceCallbacks)
        _ = runtime.renderFrame()
        for _ in 0..<4 { await Task.yield() }
        XCTAssertEqual(probe.starts, 1)
    }

    func testPendingAppearanceLaunchDoesNotRestartAKeyItsNodeHookAlreadyStarted() async {
        let child = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20))
        let runtime = makeRuntime(children: [child])
        let probe = RenderLifecycleTaskProbe()
        let taskStart = expectNextTaskStart(on: probe)
        child.pendingLifecycleTaskLaunches = [
            ViewLifecycleTaskLaunch(key: "same-key", priority: .userInitiated) {
                await probe.recordStart(version: 10)
            }
        ]
        child.onAppearWithNode = { node in
            node.launchLifecycleTask(
                ViewLifecycleTaskLaunch(key: "same-key", priority: .userInitiated) {
                    await probe.recordStart(version: 20)
                })
        }

        _ = runtime.renderScene()
        await fulfillment(of: [taskStart], timeout: 5)
        _ = runtime.renderFrame()
        for _ in 0..<4 { await Task.yield() }

        XCTAssertEqual(probe.versions, [20])
        XCTAssertEqual(probe.starts, 1)
        XCTAssertTrue(child.pendingLifecycleTaskLaunches.isEmpty)
    }

    func testNodeHookPaintMutationDefersPendingTasksWithoutRepeatingTheHook() async {
        let child = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20), backgroundColor: .black)
        let runtime = makeRuntime(children: [child])
        let probe = RenderLifecycleTaskProbe()
        var hookCalls = 0
        child.pendingLifecycleTaskLaunches = [
            ViewLifecycleTaskLaunch(key: "after-node-hook", priority: .userInitiated) {
                await probe.recordStart(version: 7)
            }
        ]
        child.onAppearWithNode = { node in
            hookCalls += 1
            node.backgroundColor = .white
        }

        _ = runtime.renderScene()

        XCTAssertEqual(hookCalls, 1)
        XCTAssertTrue(child.hasPendingAppearanceCallbacks)
        XCTAssertEqual(child.pendingLifecycleTaskLaunches.count, 1)
        XCTAssertTrue(runtime.isDirty)
        for _ in 0..<4 { await Task.yield() }
        XCTAssertEqual(probe.starts, 0)
        let taskStart = expectNextTaskStart(on: probe)
        _ = runtime.renderScene()
        XCTAssertTrue(child.pendingLifecycleTaskLaunches.isEmpty)
        await fulfillment(of: [taskStart], timeout: 5)
        XCTAssertEqual(hookCalls, 1)
        XCTAssertEqual(probe.versions, [7])
        XCTAssertEqual(probe.starts, 1)
        XCTAssertFalse(child.hasPendingAppearanceCallbacks)
        _ = runtime.renderFrame()
        for _ in 0..<4 { await Task.yield() }
        XCTAssertEqual(probe.starts, 1)
        XCTAssertEqual(hookCalls, 1)
    }

    private func expectNextTaskStart(on probe: RenderLifecycleTaskProbe) -> XCTestExpectation {
        let started = expectation(description: "Lifecycle task start \(probe.starts + 1)")
        // Yield counts are not a readiness guarantee. Acknowledge the actual
        // action after its MainActor probe has recorded the observed values.
        probe.onStart = { started.fulfill() }
        return started
    }

    private func makeRuntime(children: [ViewNode]) -> RetainedViewRuntime {
        RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120), children: children))
    }
}

@MainActor
private final class RenderLifecycleTaskProbe {
    var starts = 0
    var versions: [Int] = []
    var onStart: (() -> Void)?

    func recordStart(version: Int? = nil) {
        starts += 1
        if let version { versions.append(version) }
        let callback = onStart
        onStart = nil
        callback?()
    }
}

@MainActor
private final class RenderLifecycleBuildOwner: RetainedBuildLifecycle {
    func beginBuild() -> (any RetainedBuildEpoch)? { RenderLifecycleBuildEpoch() }
}

@MainActor
private final class RenderLifecycleBuildEpoch: RetainedBuildEpoch {
    let canAdopt = true
    func supersede() {}
    func willAdopt() -> Bool { true }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}
