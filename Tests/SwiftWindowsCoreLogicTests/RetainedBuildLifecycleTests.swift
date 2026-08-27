import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedBuildLifecycleTests: XCTestCase {
    func testEpochSpansCompositionAndNodeConstructionAndCompletesOutsideMeasurement() async throws {
        let trace = RetainedBuildTestTrace()
        let runtime = retainedBuildTestRuntime()
        runtime.collectsPhaseTimings = true
        let host = ComponentHost(runtime: runtime)
        var phase = 0
        var measureDepth = 0
        var cleanupDepth = 0
        var measuredAttempts = 0
        var measuredCleanups = 0
        host.setComponents { [weak host] in
            trace.record("compose\(phase)")
            if phase == 1 {
                XCTAssertEqual(measureDepth, 1)
                XCTAssertEqual(host?.isBuilding, true)
            }
            return [
                Component { _ in
                    trace.record("node\(phase)")
                    if phase == 1 {
                        XCTAssertEqual(measureDepth, 1)
                        XCTAssertEqual(host?.isBuilding, true)
                    }
                    return retainedBuildTestNode("value", text: "phase=\(phase)")
                }
            ]
        }
        let original = try XCTUnwrap(runtime.root.children.first)
        let lifecycle = RetainedBuildTestLifecycle(trace: trace)
        lifecycle.configure = { [weak host] epoch in
            XCTAssertEqual(measureDepth, 1, "Creating the epoch belongs to its measured attempt")
            XCTAssertEqual(host?.isBuilding, true)
            epoch.onWillAdopt = {
                XCTAssertEqual(measureDepth, 1)
                XCTAssertEqual(host?.isBuilding, true)
                XCTAssertEqual(original.text, "phase=0")
            }
            epoch.onCommit = {
                XCTAssertEqual(host?.isBuilding, true)
                XCTAssertEqual(original.text, "phase=1")
            }
            epoch.onFinish = {
                XCTAssertEqual(measureDepth, 0)
                XCTAssertEqual(cleanupDepth, 1)
                XCTAssertEqual(host?.isBuilding, true)
            }
        }
        host.buildLifecycle = lifecycle
        host.measureBuild = { [weak host] build in
            XCTAssertEqual(host?.isBuilding, true)
            measuredAttempts += 1
            measureDepth += 1
            trace.record("measure.begin")
            build()
            measureDepth -= 1
            trace.record("measure.end")
            XCTAssertEqual(host?.isBuilding, true)
        }
        host.measureBuildCleanup = { [weak host] cleanup in
            guard let host else {
                XCTFail("The component host must survive its cleanup measurement")
                return
            }
            let compose = host.lastComposeSeconds
            let construction = host.lastNodeConstructionSeconds
            let reconciliation = host.lastReconcileSeconds
            XCTAssertEqual(measureDepth, 0)
            XCTAssertTrue(host.isBuilding)
            measuredCleanups += 1
            cleanupDepth += 1
            trace.record("cleanup.measure.begin")
            cleanup()
            cleanupDepth -= 1
            trace.record("cleanup.measure.end")
            XCTAssertEqual(host.lastComposeSeconds, compose)
            XCTAssertEqual(host.lastNodeConstructionSeconds, construction)
            XCTAssertEqual(host.lastReconcileSeconds, reconciliation)
            XCTAssertTrue(host.isBuilding)
        }
        host.onReloadCompleted = { [weak host] in
            XCTAssertEqual(measureDepth, 0)
            XCTAssertEqual(cleanupDepth, 0)
            XCTAssertEqual(host?.isBuilding, true)
            trace.record("host.complete")
        }
        trace.clear()
        phase = 1

        runtime.beginLongPressReconciliation()
        host.reload(onCompleted: {
            XCTAssertEqual(measureDepth, 0)
            XCTAssertEqual(cleanupDepth, 0)
            XCTAssertTrue(host.isBuilding)
            trace.record("request.complete")
        })

        XCTAssertEqual(measureDepth, 0)
        XCTAssertTrue(host.isBuilding, "The guard includes callbacks waiting behind an enclosing scope")
        XCTAssertEqual(lifecycle.epochs.first?.commitCount, 1)
        XCTAssertEqual(lifecycle.epochs.first?.finishCount, 0)
        XCTAssertEqual(measuredCleanups, 0)
        XCTAssertFalse(trace.events.contains("request.complete"))
        runtime.endLongPressReconciliation()

        XCTAssertTrue(runtime.root.children.first === original)
        XCTAssertEqual(original.text, "phase=1")
        XCTAssertEqual(measuredAttempts, 1)
        XCTAssertEqual(measuredCleanups, 1)
        XCTAssertEqual(lifecycle.epochs.count, 1)
        XCTAssertEqual(lifecycle.epochs.first?.commitCount, 1)
        XCTAssertEqual(lifecycle.epochs.first?.abandonCount, 0)
        XCTAssertEqual(lifecycle.epochs.first?.finishCount, 1)
        trace.assertBefore("root1.begin", "compose1")
        trace.assertBefore("measure.begin", "root1.begin")
        trace.assertBefore("measure.begin", "compose1")
        trace.assertBefore("compose1", "node1")
        trace.assertBefore("node1", "root1.willAdopt")
        trace.assertBefore("root1.willAdopt", "root1.commit")
        trace.assertBefore("root1.commit", "root1.finish")
        trace.assertBefore("measure.end", "root1.finish")
        trace.assertBefore("root1.finish", "host.complete")
        trace.assertBefore("cleanup.measure.begin", "root1.finish")
        trace.assertBefore("cleanup.measure.end", "host.complete")
        trace.assertBefore("measure.end", "request.complete")
        trace.assertBefore("host.complete", "request.complete")
        XCTAssertFalse(runtime.hasActiveRetainedBuild)
    }

    func testRejectedBeginOrInactiveEpochDoesNotComposeOrReplaceTheOldTree() async throws {
        for returnsNil in [true, false] {
            let trace = RetainedBuildTestTrace()
            let runtime = retainedBuildTestRuntime()
            runtime.collectsPhaseTimings = true
            let host = ComponentHost(runtime: runtime)
            var compositions = 0
            host.setComponents {
                compositions += 1
                return [Component { _ in retainedBuildTestNode("value", text: "old") }]
            }
            let original = try XCTUnwrap(runtime.root.children.first)
            XCTAssertGreaterThan(
                host.lastComposeSeconds + host.lastNodeConstructionSeconds + host.lastReconcileSeconds, 0)
            let lifecycle = RetainedBuildTestLifecycle(trace: trace)
            lifecycle.rejectBegin = returnsNil
            lifecycle.configure = { $0.canAdopt = false }
            host.buildLifecycle = lifecycle
            var completions = 0
            host.onReloadCompleted = { completions += 1 }
            compositions = 0

            host.reload(onCompleted: { completions += 1 })

            XCTAssertEqual(compositions, 0)
            XCTAssertEqual(completions, 0)
            XCTAssertTrue(runtime.root.children.first === original)
            XCTAssertEqual(original.text, "old")
            XCTAssertEqual(host.lastComposeSeconds, 0)
            XCTAssertEqual(host.lastNodeConstructionSeconds, 0)
            XCTAssertEqual(host.lastReconcileSeconds, 0)
            XCTAssertEqual(lifecycle.beginCount, 1)
            if returnsNil {
                XCTAssertTrue(lifecycle.epochs.isEmpty)
                XCTAssertEqual(trace.events, ["root1.begin"])
            } else {
                XCTAssertEqual(trace.events, ["root1.begin", "root1.abandon", "root1.finish"])
                XCTAssertEqual(lifecycle.epochs.first?.finishCount, 1)
            }
            XCTAssertFalse(runtime.hasActiveRetainedBuild)
        }
    }

    func testPreparationRejectionLeavesNodesUntouchedAndClearsPreviousPhaseTimings() async throws {
        let trace = RetainedBuildTestTrace()
        let runtime = retainedBuildTestRuntime()
        runtime.collectsPhaseTimings = true
        let host = ComponentHost(runtime: runtime)
        var phase = 0
        var nodesBuilt = 0
        host.setComponents {
            trace.record("compose\(phase)")
            return (0..<24).map { index in
                Component { _ in
                    nodesBuilt += 1
                    return retainedBuildTestNode("value\(index)", text: "phase=\(phase)")
                }
            }
        }
        let original = try XCTUnwrap(runtime.root.children.first)
        XCTAssertGreaterThan(host.lastComposeSeconds + host.lastNodeConstructionSeconds + host.lastReconcileSeconds, 0)
        XCTAssertGreaterThan(host.lastReconcileSeconds, 0, "The rejected attempt must replace a measured old reconcile")
        let lifecycle = RetainedBuildTestLifecycle(trace: trace)
        lifecycle.configure = { $0.acceptsAdoption = false }
        host.buildLifecycle = lifecycle
        var completions = 0
        host.onReloadCompleted = { completions += 1 }
        nodesBuilt = 0
        trace.clear()
        phase = 1

        host.reload(onCompleted: { completions += 1 })

        XCTAssertEqual(nodesBuilt, 24)
        XCTAssertEqual(runtime.root.children.count, 24)
        XCTAssertTrue(runtime.root.children.first === original)
        XCTAssertEqual(original.text, "phase=0")
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(trace.events, ["root1.begin", "compose1", "root1.willAdopt", "root1.abandon", "root1.finish"])
        XCTAssertGreaterThanOrEqual(host.lastComposeSeconds, 0)
        XCTAssertGreaterThanOrEqual(host.lastNodeConstructionSeconds, 0)
        XCTAssertEqual(host.lastReconcileSeconds, 0)
        XCTAssertFalse(runtime.hasActiveRetainedBuild)
    }

    func testReloadDuringCompositionSupersedesTheCandidateAndKeepsTheNewRequestsTransaction() async throws {
        try assertConstructionSupersession(duringNodeConstruction: false)
    }

    func testReloadDuringNodeConstructionSupersedesBeforeAnyCandidateIsAdopted() async throws {
        try assertConstructionSupersession(duringNodeConstruction: true)
    }

    func testDisappearanceKeepsEachQueuedRequestsTransactionAndCompletionInOrder() async throws {
        let trace = RetainedBuildTestTrace()
        let runtime = retainedBuildTestRuntime()
        let host = ComponentHost(runtime: runtime)
        let original = retainedBuildTestNode("old", text: "old")
        var phase = 0
        var composition = 0
        host.setComponents {
            let candidatePhase = phase
            if candidatePhase != 0 { composition += 1 }
            trace.record("compose\(composition)")
            return [
                Component { _ in
                    candidatePhase == 0
                        ? original : retainedBuildTestNode("phase\(candidatePhase)", text: "phase=\(candidatePhase)")
                }
            ]
        }
        _ = runtime.renderFrame()
        XCTAssertTrue(original.hasAppeared)
        let lifecycle = RetainedBuildTestLifecycle(trace: trace)
        host.buildLifecycle = lifecycle
        var completions: [String] = []
        var measuredAttempts = 0
        var isMeasuring = false
        host.measureBuild = { [weak host] build in
            XCTAssertEqual(host?.isBuilding, true)
            measuredAttempts += 1
            isMeasuring = true
            build()
            isMeasuring = false
        }
        original.onDisappear = { [weak host] in
            guard let host else {
                XCTFail("The component host must survive its disappearance callback")
                return
            }
            trace.record("disappear.begin")
            phase = 2
            withRetainedBuildTestTransaction(retainedBuildTestTransaction(animation: .linear(duration: 0.75))) {
                host.reload(onCompleted: {
                    XCTAssertFalse(isMeasuring)
                    XCTAssertTrue(host.isBuilding)
                    trace.record("animated.complete")
                    completions.append("animated")
                })
            }
            phase = 3
            var transaction = retainedBuildTestTransaction(animation: nil)
            transaction.disablesAnimations = true
            withRetainedBuildTestTransaction(transaction) {
                host.reload(onCompleted: {
                    XCTAssertFalse(isMeasuring)
                    XCTAssertTrue(host.isBuilding)
                    trace.record("nil.complete")
                    completions.append("nil")
                })
            }
            XCTAssertFalse(trace.events.contains("compose2"))
            XCTAssertFalse(trace.events.contains("compose3"))
            trace.record("disappear.end")
        }
        trace.clear()
        phase = 1

        withRetainedBuildTestTransaction(Transaction(animation: .linear(duration: 4))) {
            host.reload(onCompleted: {
                XCTAssertFalse(isMeasuring)
                XCTAssertTrue(host.isBuilding)
                trace.record("first.complete")
                completions.append("first")
            })
        }

        XCTAssertEqual(runtime.root.children.first?.text, "phase=3")
        XCTAssertEqual(completions, ["first", "animated", "nil"])
        XCTAssertEqual(measuredAttempts, 3, "Measure actual attempts, without counting their deferred completions")
        XCTAssertEqual(lifecycle.epochs.map(\.commitCount), [1, 1, 1])
        XCTAssertEqual(lifecycle.epochs.map(\.abandonCount), [0, 0, 0])
        XCTAssertEqual(lifecycle.epochs.map(\.finishCount), [1, 1, 1])
        trace.assertBefore("root1.willAdopt", "disappear.begin")
        trace.assertBefore("disappear.end", "root1.commit")
        trace.assertBefore("root1.finish", "first.complete")
        trace.assertBefore("first.complete", "root2.begin")
        trace.assertBefore("root2.finish", "animated.complete")
        trace.assertBefore("animated.complete", "root3.begin")
        trace.assertBefore("root3.finish", "nil.complete")
        try assertFullTransaction(in: trace, event: "compose2", duration: 0.75)
        try assertFullTransaction(in: trace, event: "animated.complete", duration: 0.75)
        try assertFullTransaction(in: trace, event: "compose3", duration: nil, disablesAnimations: true)
        try assertFullTransaction(in: trace, event: "nil.complete", duration: nil, disablesAnimations: true)
        XCTAssertEqual(trace.scopes["first.complete"]?.transaction?.animation?.duration, 4)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
        XCTAssertFalse(runtime.hasActiveRetainedBuild)
    }

    func testCommittedEpochFinishesAfterTerminalLongPressCallbacksAndBeforeTheirQueuedReload() async throws {
        let trace = RetainedBuildTestTrace()
        let runtime = retainedBuildTestRuntime()
        runtime.clock = { 10 }
        let host = ComponentHost(runtime: runtime)
        var phase = 0
        var completions: [String] = []
        var pressing: [Bool] = []
        host.setComponents { [weak host] in
            let candidatePhase = phase
            trace.record("compose\(candidatePhase)")
            return [
                Component { _ in
                    let node = retainedBuildTestNode("press", text: "phase=\(candidatePhase)")
                    if candidatePhase == 0 {
                        node.longPressGesture = RetainedLongPressGesture(
                            minimumDuration: 100,
                            onBegin: { _ in { trace.record("press.cleanup") } },
                            onPressingChanged: { isPressing in
                                pressing.append(isPressing)
                                guard !isPressing else { return }
                                guard let host else {
                                    XCTFail("The component host must survive its terminal callback")
                                    return
                                }
                                XCTAssertTrue(host.isBuilding)
                                trace.record("press.terminal.begin")
                                phase = 2
                                host.reload(onCompleted: {
                                    XCTAssertTrue(host.isBuilding)
                                    trace.record("terminal.request.complete")
                                    completions.append("terminal")
                                })
                                XCTAssertFalse(trace.events.contains("compose2"))
                                trace.record("press.terminal.end")
                            },
                            onRecognized: { XCTFail("The held gesture must be cancelled, not recognized") }
                        )
                    }
                    return node
                }
            ]
        }
        let original = try XCTUnwrap(runtime.root.children.first)
        _ = runtime.renderFrame()
        runtime.pointerDown(at: Point(x: 20, y: 20))
        XCTAssertEqual(pressing, [true])
        let lifecycle = RetainedBuildTestLifecycle(trace: trace)
        host.buildLifecycle = lifecycle
        trace.clear()
        phase = 1

        host.reload(onCompleted: {
            trace.record("first.request.complete")
            completions.append("first")
        })

        XCTAssertTrue(runtime.root.children.first === original)
        XCTAssertEqual(original.text, "phase=2")
        XCTAssertEqual(pressing, [true, false])
        XCTAssertEqual(completions, ["first", "terminal"])
        XCTAssertEqual(lifecycle.epochs.map(\.commitCount), [1, 1])
        XCTAssertEqual(lifecycle.epochs.map(\.finishCount), [1, 1])
        trace.assertBefore("root1.commit", "press.terminal.begin")
        trace.assertBefore("press.terminal.end", "press.cleanup")
        trace.assertBefore("press.cleanup", "root1.finish")
        trace.assertBefore("first.request.complete", "root2.begin")
        trace.assertBefore("root2.finish", "terminal.request.complete")
        XCTAssertFalse(runtime.hasActiveRetainedBuild)
    }

    func testRootBuildPreventsNestedGeometryConstructionUntilItsOwnAttemptFinishes() async throws {
        let trace = RetainedBuildTestTrace()
        let runtime = retainedBuildTestRuntime()
        let host = ComponentHost(runtime: runtime)
        let lease = RetainedBuildTestSubtreeLease(trace: trace)
        let geometry = RetainedBuildTestGeometry(trace: trace, lease: lease)
        let seed = Size(width: 60, height: 40)
        let resized = Size(width: 120, height: 80)
        var phase = 0
        host.setComponents {
            trace.record("compose\(phase)")
            if phase == 1 {
                _ = runtime.renderFrame()
                XCTAssertEqual(geometry.bodyCount, 0)
                XCTAssertEqual(lease.beginCount, 0)
                trace.record("nested.render.returned")
            }
            let size = phase == 0 ? seed : resized
            return [Component { _ in geometry.makeNode(frameSize: size, builtSize: seed) }]
        }
        let original = try XCTUnwrap(runtime.root.children.first)
        let lifecycle = RetainedBuildTestLifecycle(trace: trace)
        host.buildLifecycle = lifecycle
        original.frame.size = resized
        phase = 1
        trace.clear()

        host.reload(onCompleted: {
            // A completion can paint while the root coordinator still owns
            // this attempt. That skipped reader must stay eligible afterward.
            _ = runtime.renderScene()
            XCTAssertEqual(geometry.bodyCount, 0)
            XCTAssertEqual(lease.beginCount, 0)
            trace.record("completion.render.returned")
            trace.record("root.request.complete")
        })

        XCTAssertEqual(geometry.bodyCount, 0)
        XCTAssertEqual(lease.beginCount, 0)
        XCTAssertTrue(runtime.root.children.first === original)
        XCTAssertTrue(original.retainedSubtreeBuildLease === lease)
        XCTAssertTrue(runtime.isDirty, "Skipping a busy reader must request layout after the guard is released")
        _ = runtime.renderScene()

        XCTAssertEqual(geometry.bodyCount, 1)
        XCTAssertEqual(lease.beginCount, 1)
        XCTAssertEqual(lease.epochs.first?.commitCount, 1)
        XCTAssertEqual(lease.epochs.first?.finishCount, 1)
        XCTAssertEqual(original.geometryReaderBuiltSize, resized)
        XCTAssertEqual(original.children.first?.text, "built")
        XCTAssertTrue(original.retainedSubtreeBuildLease === lease)
        trace.assertBefore("nested.render.returned", "root1.commit")
        trace.assertBefore("root1.finish", "completion.render.returned")
        trace.assertBefore("root.request.complete", "geometry1.begin")
        trace.assertBefore("geometry1.begin", "geometry.body")
        trace.assertBefore("geometry.node", "geometry1.willAdopt")
        trace.assertBefore("geometry1.commit", "geometry1.finish")
        XCTAssertFalse(runtime.hasActiveRetainedBuild)
    }

    func testGeometryConstructionQueuesARootReloadAndAbandonsItsObsoleteCandidate() async throws {
        let trace = RetainedBuildTestTrace()
        let runtime = retainedBuildTestRuntime()
        let host = ComponentHost(runtime: runtime)
        let lease = RetainedBuildTestSubtreeLease(trace: trace)
        let geometry = RetainedBuildTestGeometry(trace: trace, lease: lease)
        let seed = Size(width: 60, height: 40)
        var phase = 0
        host.setComponents {
            trace.record("compose\(phase)")
            return [
                Component { _ in
                    phase == 0
                        ? geometry.makeNode(frameSize: seed, builtSize: seed)
                        : retainedBuildTestNode("replacement", text: "replacement")
                }
            ]
        }
        let original = try XCTUnwrap(runtime.root.children.first)
        let lifecycle = RetainedBuildTestLifecycle(trace: trace)
        host.buildLifecycle = lifecycle
        geometry.onBuild = { [weak host] _, _ in
            guard let host else {
                XCTFail("The component host must survive its subtree builder")
                return
            }
            phase = 1
            host.reload(onCompleted: { trace.record("root.request.complete") })
            XCTAssertFalse(trace.events.contains("compose1"))
            trace.record("geometry.request.returned")
        }
        trace.clear()
        original.frame.size = Size(width: 120, height: 80)

        _ = runtime.renderFrame()

        XCTAssertEqual(geometry.bodyCount, 1)
        XCTAssertEqual(lease.epochs.first?.commitCount, 0)
        XCTAssertEqual(lease.epochs.first?.abandonCount, 1)
        XCTAssertEqual(lease.epochs.first?.finishCount, 1)
        XCTAssertEqual(lifecycle.epochs.first?.commitCount, 1)
        XCTAssertEqual(runtime.root.children.first?.text, "replacement")
        XCTAssertNil(original.parent)
        XCTAssertEqual(original.geometryReaderBuiltSize, seed)
        XCTAssertEqual(runtime.geometryReaderResolveCount, 0)
        XCTAssertFalse(trace.events.contains("geometry1.willAdopt"))
        trace.assertBefore("geometry.request.returned", "geometry1.abandon")
        trace.assertBefore("geometry1.finish", "root1.begin")
        trace.assertBefore("root1.finish", "root.request.complete")
        XCTAssertFalse(runtime.hasActiveRetainedBuild)
    }

    func testInvalidOrRejectedSubtreeLeaseNeverEvaluatesItsGeometryBuilder() async throws {
        for invalidLease in [true, false] {
            let trace = RetainedBuildTestTrace()
            let runtime = retainedBuildTestRuntime()
            let lease = RetainedBuildTestSubtreeLease(trace: trace)
            lease.canBuild = !invalidLease
            lease.rejectBegin = !invalidLease
            let geometry = RetainedBuildTestGeometry(trace: trace, lease: lease)
            let seed = Size(width: 60, height: 40)
            let reader = geometry.makeNode(frameSize: Size(width: 120, height: 80), builtSize: seed)
            runtime.root.addChild(reader)

            _ = runtime.renderFrame()

            XCTAssertEqual(geometry.bodyCount, 0)
            XCTAssertEqual(lease.beginCount, invalidLease ? 0 : 1)
            XCTAssertTrue(lease.epochs.isEmpty)
            XCTAssertEqual(reader.geometryReaderBuiltSize, seed)
            XCTAssertEqual(reader.children.first?.text, "seed")
            XCTAssertTrue(runtime.root.children.first === reader)
            XCTAssertEqual(runtime.geometryReaderResolveCount, 0)
            XCTAssertFalse(runtime.hasActiveRetainedBuild)
        }
    }

    func testGeometryLeaseInvalidationOrReplacementDuringConstructionRejectsAdoption() async throws {
        for replacesLease in [false, true] {
            let trace = RetainedBuildTestTrace()
            let runtime = retainedBuildTestRuntime()
            let lease = RetainedBuildTestSubtreeLease(trace: trace)
            let replacementLease = RetainedBuildTestSubtreeLease(trace: trace, name: "replacement")
            let geometry = RetainedBuildTestGeometry(trace: trace, lease: lease)
            let seed = Size(width: 60, height: 40)
            let reader = geometry.makeNode(frameSize: Size(width: 120, height: 80), builtSize: seed)
            let originalContent = try XCTUnwrap(reader.children.first)
            runtime.root.addChild(reader)
            geometry.onBuild = { [weak reader] _, _ in
                if replacesLease {
                    reader?.retainedSubtreeBuildLease = replacementLease
                } else {
                    lease.canBuild = false
                }
            }

            _ = runtime.renderFrame()

            XCTAssertEqual(geometry.bodyCount, 1)
            XCTAssertEqual(lease.epochs.first?.commitCount, 0)
            XCTAssertEqual(lease.epochs.first?.abandonCount, 1)
            XCTAssertEqual(lease.epochs.first?.finishCount, 1)
            XCTAssertEqual(replacementLease.beginCount, 0)
            XCTAssertFalse(trace.events.contains("geometry1.willAdopt"))
            XCTAssertTrue(reader.children.first === originalContent)
            XCTAssertEqual(originalContent.text, "seed")
            XCTAssertEqual(reader.geometryReaderBuiltSize, seed)
            XCTAssertEqual(runtime.geometryReaderResolveCount, 0)
            if replacesLease { XCTAssertTrue(reader.retainedSubtreeBuildLease === replacementLease) }
            XCTAssertFalse(runtime.hasActiveRetainedBuild)
        }
    }

    func testAdoptionPreservesOrReplacesTheSubtreeLeaseAndClearsAnAbsentSourceLease() async throws {
        let trace = RetainedBuildTestTrace()
        let runtime = retainedBuildTestRuntime()
        let host = ComponentHost(runtime: runtime)
        let first = RetainedBuildTestSubtreeLease(trace: trace, name: "first")
        let second = RetainedBuildTestSubtreeLease(trace: trace, name: "second")
        var nextLease: (any RetainedSubtreeBuildLease)? = first
        host.setComponents {
            [
                Component { _ in
                    let node = retainedBuildTestNode("stable", text: "value")
                    node.retainedSubtreeBuildLease = nextLease
                    return node
                }
            ]
        }
        let original = try XCTUnwrap(runtime.root.children.first)

        host.reload()
        XCTAssertTrue(runtime.root.children.first === original)
        XCTAssertTrue(original.retainedSubtreeBuildLease === first)
        nextLease = second
        host.reload()
        XCTAssertTrue(runtime.root.children.first === original)
        XCTAssertTrue(original.retainedSubtreeBuildLease === second)
        nextLease = nil
        host.reload()

        XCTAssertTrue(runtime.root.children.first === original)
        XCTAssertNil(original.retainedSubtreeBuildLease)
        XCTAssertEqual(first.beginCount, 0)
        XCTAssertEqual(second.beginCount, 0)
    }

    func testRequestReceiptsRejectStaleQueuedAndPartiallyConstructedRequests() async throws {
        for changesRevisionInCompletion in [false, true] {
            let trace = RetainedBuildTestTrace()
            let runtime = retainedBuildTestRuntime()
            let host = ComponentHost(runtime: runtime)
            let revision = RetainedBuildTestRevision()
            let original = retainedBuildTestNode("old", text: "old")
            var phase = 0
            host.setComponents {
                let candidatePhase = phase
                return [
                    Component { _ in
                        if candidatePhase == 0 { return original }
                        return retainedBuildTestNode("phase\(candidatePhase)", text: "phase=\(candidatePhase)")
                    }
                ]
            }
            _ = runtime.renderFrame()
            XCTAssertTrue(original.hasAppeared)
            let lifecycle = RetainedBuildTestLifecycle(trace: trace)
            lifecycle.requestRevision = revision
            host.buildLifecycle = lifecycle
            var measuredAttempts = 0
            host.measureBuild = { build in
                measuredAttempts += 1
                build()
            }
            var completions: [String] = []
            original.onDisappear = { [weak host] in
                guard let host else {
                    XCTFail("The component host must survive its receipt fixture")
                    return
                }
                phase = 2
                revision.value = 1
                host.reload(onCompleted: {
                    completions.append("B")
                    trace.record("B.complete")
                    if changesRevisionInCompletion {
                        phase = 3
                        revision.value = 2
                        host.reload(onCompleted: {
                            completions.append("D")
                            trace.record("D.complete")
                        })
                    }
                })
                if !changesRevisionInCompletion {
                    phase = 3
                    revision.value = 2
                }
                host.reload(onCompleted: {
                    completions.append("C")
                    trace.record("C.complete")
                })
            }
            phase = 1

            host.reload(onCompleted: {
                completions.append("A")
                trace.record("A.complete")
            })

            let expectedAttempts = changesRevisionInCompletion ? 3 : 2
            XCTAssertEqual(completions, changesRevisionInCompletion ? ["A", "B", "D"] : ["A", "C"])
            XCTAssertEqual(lifecycle.capturedRevisions, changesRevisionInCompletion ? [0, 1, 1, 2] : [0, 1, 2])
            XCTAssertEqual(
                measuredAttempts, expectedAttempts, "A stale queued receipt must not begin a measured attempt")
            XCTAssertEqual(lifecycle.beginCount, expectedAttempts)
            XCTAssertEqual(lifecycle.epochs.map(\.commitCount), Array(repeating: 1, count: expectedAttempts))
            XCTAssertEqual(lifecycle.epochs.map(\.abandonCount), Array(repeating: 0, count: expectedAttempts))
            XCTAssertEqual(lifecycle.epochs.map(\.finishCount), Array(repeating: 1, count: expectedAttempts))
            XCTAssertEqual(runtime.root.children.first?.text, "phase=3")
            trace.assertBefore("root1.finish", "A.complete")
            if changesRevisionInCompletion {
                trace.assertBefore("B.complete", "root3.begin")
                trace.assertBefore("root3.finish", "D.complete")
            } else {
                trace.assertBefore("root2.finish", "C.complete")
            }
            XCTAssertFalse(host.isBuilding)
        }

        for stage in RetainedBuildTestReceiptInvalidation.allCases {
            let trace = RetainedBuildTestTrace()
            let runtime = retainedBuildTestRuntime()
            let host = ComponentHost(runtime: runtime)
            let revision = RetainedBuildTestRevision()
            var phase = 0
            var nodesBuilt = 0
            host.setComponents {
                let candidatePhase = phase
                trace.record("compose\(candidatePhase)")
                if candidatePhase == 1, stage == .composition { revision.value += 1 }
                return [
                    Component { _ in
                        if candidatePhase == 1 {
                            nodesBuilt += 1
                            if stage == .nodeConstruction { revision.value += 1 }
                        }
                        return retainedBuildTestNode("phase\(candidatePhase)", text: "phase=\(candidatePhase)")
                    }
                ]
            }
            let original = try XCTUnwrap(runtime.root.children.first)
            let lifecycle = RetainedBuildTestLifecycle(trace: trace)
            lifecycle.requestRevision = revision
            lifecycle.configure = { epoch in
                if stage == .preparation {
                    epoch.onWillAdopt = { revision.value += 1 }
                }
            }
            host.buildLifecycle = lifecycle
            var measuredAttempts = 0
            var completions = 0
            host.measureBuild = { build in
                measuredAttempts += 1
                build()
            }
            phase = 1
            trace.clear()

            host.reload(onCompleted: { completions += 1 })

            XCTAssertEqual(lifecycle.capturedRevisions, [0])
            XCTAssertEqual(measuredAttempts, 1)
            XCTAssertEqual(completions, 0, "A receipt invalidated during \(stage) must not complete")
            XCTAssertEqual(nodesBuilt, stage == .composition ? 0 : 1)
            XCTAssertEqual(lifecycle.epochs.first?.commitCount, 0)
            XCTAssertEqual(lifecycle.epochs.first?.abandonCount, 1)
            XCTAssertEqual(lifecycle.epochs.first?.finishCount, 1)
            XCTAssertEqual(trace.events.contains("root1.willAdopt"), stage == .preparation)
            XCTAssertTrue(runtime.root.children.first === original)
            XCTAssertEqual(original.text, "phase=0")
            trace.assertBefore("root1.abandon", "root1.finish")
            XCTAssertFalse(host.isBuilding)
        }
    }

    func testNewRevisionDuringAdoptionKeepsCompletionButOwnerClosureSuppressesIt() async throws {
        for change in RetainedBuildTestCompletionChange.allCases {
            let trace = RetainedBuildTestTrace()
            let runtime = retainedBuildTestRuntime()
            let host = ComponentHost(runtime: runtime)
            let revision = RetainedBuildTestRevision()
            let lifecycle = RetainedBuildTestLifecycle(trace: trace)
            lifecycle.requestRevision = revision
            var phase = 0
            var completions: [String] = []
            var sharedCompletions = 0
            var measuredAttempts = 0
            var measuredCleanups = 0
            host.setComponents {
                let candidatePhase = phase
                return [
                    Component { _ in
                        retainedBuildTestNode("phase\(candidatePhase)", text: "phase=\(candidatePhase)")
                    }
                ]
            }
            _ = runtime.renderFrame()
            let original = try XCTUnwrap(runtime.root.children.first)
            XCTAssertTrue(original.hasAppeared)
            let closeOwner = { [weak lifecycle] in
                guard let lifecycle else {
                    XCTFail("The build lifecycle must survive its adoption")
                    return
                }
                lifecycle.rejectBegin = true
                for epoch in lifecycle.epochs { epoch.canComplete = false }
                trace.record("owner.closed")
            }
            original.onDisappear = { [weak host] in
                trace.record("original.disappear")
                XCTAssertEqual(host?.isBuilding, true)
                if change == .closeDuringAdoption {
                    closeOwner()
                } else if change == .revisionDuringAdoption {
                    phase = 2
                    revision.value += 1
                    withRetainedBuildTestTransaction(retainedBuildTestTransaction(animation: .linear(duration: 0.4))) {
                        host?.reload(onCompleted: {
                            completions.append("B")
                            trace.record("B.complete")
                        })
                    }
                }
            }
            lifecycle.configure = { epoch in
                guard epoch.name == "root1" else { return }
                if change == .closeDuringCommit { epoch.onCommit = closeOwner }
                if change == .closeDuringCleanup { epoch.onFinish = closeOwner }
            }
            host.buildLifecycle = lifecycle
            host.measureBuild = { build in
                measuredAttempts += 1
                build()
            }
            host.measureBuildCleanup = { cleanup in
                measuredCleanups += 1
                cleanup()
            }
            host.onReloadCompleted = { [weak host] in
                XCTAssertEqual(host?.isBuilding, true)
                sharedCompletions += 1
                trace.record("shared.complete\(sharedCompletions)")
                if change == .closeDuringSharedCompletion { closeOwner() }
            }
            trace.clear()
            phase = 1

            withRetainedBuildTestTransaction(retainedBuildTestTransaction(animation: .linear(duration: 0.8))) {
                host.reload(onCompleted: {
                    completions.append("A")
                    trace.record("A.complete")
                })
            }

            let changesRevision = change == .revisionDuringAdoption
            let attempts = changesRevision ? 2 : 1
            XCTAssertEqual(measuredAttempts, attempts, "\(change)")
            XCTAssertEqual(measuredCleanups, attempts, "\(change)")
            XCTAssertEqual(lifecycle.epochs.map(\.commitCount), Array(repeating: 1, count: attempts), "\(change)")
            XCTAssertEqual(lifecycle.epochs.map(\.abandonCount), Array(repeating: 0, count: attempts), "\(change)")
            XCTAssertEqual(lifecycle.epochs.map(\.finishCount), Array(repeating: 1, count: attempts), "\(change)")
            XCTAssertEqual(completions, changesRevision ? ["A", "B"] : [], "\(change)")
            XCTAssertEqual(runtime.root.children.first?.text, changesRevision ? "phase=2" : "phase=1", "\(change)")
            trace.assertBefore("root1.willAdopt", "original.disappear")
            trace.assertBefore("original.disappear", "root1.commit")
            trace.assertBefore("root1.commit", "root1.finish")
            if changesRevision {
                XCTAssertEqual(sharedCompletions, 2)
                XCTAssertEqual(lifecycle.capturedRevisions, [0, 1])
                trace.assertBefore("root1.finish", "A.complete")
                trace.assertBefore("A.complete", "root2.begin")
                trace.assertBefore("root2.finish", "B.complete")
                try assertFullTransaction(in: trace, event: "A.complete", duration: 0.8)
                try assertFullTransaction(in: trace, event: "B.complete", duration: 0.4)
            } else {
                XCTAssertEqual(sharedCompletions, change == .closeDuringSharedCompletion ? 1 : 0)
                XCTAssertFalse(trace.events.contains("A.complete"))
                XCTAssertTrue(trace.events.contains("owner.closed"))
            }
            XCTAssertFalse(host.isBuilding)
            XCTAssertNil(currentTransaction)
            XCTAssertNil(currentAnimationTransaction)
        }
    }

    private func assertConstructionSupersession(
        duringNodeConstruction: Bool, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let trace = RetainedBuildTestTrace()
        let runtime = retainedBuildTestRuntime()
        let host = ComponentHost(runtime: runtime)
        var phase = 0
        var completions: [String] = []
        let requestReplacement = { [weak host] in
            guard let host else {
                XCTFail("The component host must survive its candidate builder", file: file, line: line)
                return
            }
            phase = 2
            withRetainedBuildTestTransaction(retainedBuildTestTransaction(animation: .linear(duration: 0.75))) {
                host.reload(onCompleted: {
                    trace.record("replacement.complete")
                    completions.append("replacement")
                })
            }
            XCTAssertFalse(trace.events.contains("compose2"), file: file, line: line)
            trace.record("superseding.request.returned")
        }
        host.setComponents {
            let candidatePhase = phase
            trace.record("compose\(candidatePhase)")
            if candidatePhase == 1, !duringNodeConstruction { requestReplacement() }
            return [
                Component { _ in
                    trace.record("node\(candidatePhase)")
                    if candidatePhase == 1, duringNodeConstruction { requestReplacement() }
                    return retainedBuildTestNode("phase\(candidatePhase)", text: "phase=\(candidatePhase)")
                }
            ]
        }
        let original = try XCTUnwrap(runtime.root.children.first, file: file, line: line)
        let lifecycle = RetainedBuildTestLifecycle(trace: trace)
        lifecycle.configure = { epoch in
            guard epoch.name == "root1" else { return }
            epoch.onFinish = {
                XCTAssertTrue(runtime.root.children.first === original, file: file, line: line)
                XCTAssertEqual(original.text, "phase=0", file: file, line: line)
            }
        }
        host.buildLifecycle = lifecycle
        trace.clear()
        phase = 1

        host.reload(onCompleted: { completions.append("superseded") })

        XCTAssertEqual(runtime.root.children.first?.text, "phase=2", file: file, line: line)
        XCTAssertEqual(completions, ["replacement"], file: file, line: line)
        XCTAssertEqual(lifecycle.epochs.map(\.commitCount), [0, 1], file: file, line: line)
        XCTAssertEqual(lifecycle.epochs.map(\.abandonCount), [1, 0], file: file, line: line)
        XCTAssertEqual(lifecycle.epochs.map(\.finishCount), [1, 1], file: file, line: line)
        XCTAssertFalse(trace.events.contains("root1.willAdopt"), file: file, line: line)
        trace.assertBefore("superseding.request.returned", "root1.abandon", file: file, line: line)
        trace.assertBefore("root1.finish", "root2.begin", file: file, line: line)
        trace.assertBefore("root2.finish", "replacement.complete", file: file, line: line)
        try assertFullTransaction(in: trace, event: "compose2", duration: 0.75, file: file, line: line)
        try assertFullTransaction(in: trace, event: "replacement.complete", duration: 0.75, file: file, line: line)
        XCTAssertNil(currentTransaction, file: file, line: line)
        XCTAssertNil(currentAnimationTransaction, file: file, line: line)
        XCTAssertFalse(runtime.hasActiveRetainedBuild, file: file, line: line)
    }

    private func assertFullTransaction(
        in trace: RetainedBuildTestTrace, event: String, duration: Double?, disablesAnimations: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let scope = try XCTUnwrap(trace.scopes[event], file: file, line: line)
        let transaction = try XCTUnwrap(scope.transaction, file: file, line: line)
        XCTAssertEqual(transaction.animation?.duration, duration, file: file, line: line)
        XCTAssertEqual(transaction.animation?.easing, duration == nil ? nil : .linear, file: file, line: line)
        XCTAssertEqual(transaction.disablesAnimations, disablesAnimations, file: file, line: line)
        XCTAssertTrue(transaction.isContinuous, file: file, line: line)
        XCTAssertEqual(transaction.scrollTargetAnchor, .trailing, file: file, line: line)
        XCTAssertTrue(transaction.tracksVelocity, file: file, line: line)
        XCTAssertEqual(scope.animationDuration, duration, file: file, line: line)
        XCTAssertEqual(scope.animationEasing, duration == nil ? nil : .linear, file: file, line: line)
    }
}

private struct RetainedBuildTestScope {
    let transaction: Transaction?
    let animationDuration: Double?
    let animationEasing: AnimationEasing?
}

@MainActor
private final class RetainedBuildTestTrace {
    private(set) var events: [String] = []
    private(set) var scopes: [String: RetainedBuildTestScope] = [:]

    func record(_ event: String) {
        events.append(event)
        scopes[event] = RetainedBuildTestScope(
            transaction: currentTransaction, animationDuration: currentAnimationTransaction?.duration,
            animationEasing: currentAnimationTransaction?.easing)
    }

    func clear() {
        events.removeAll()
        scopes.removeAll()
    }

    func assertBefore(_ earlier: String, _ later: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let earlierIndex = events.firstIndex(of: earlier), let laterIndex = events.firstIndex(of: later) else {
            XCTFail("Missing \(earlier) or \(later) in \(events)", file: file, line: line)
            return
        }
        XCTAssertLessThan(earlierIndex, laterIndex, "Unexpected lifecycle order: \(events)", file: file, line: line)
    }
}

@MainActor
private final class RetainedBuildTestEpoch: RetainedBuildEpoch {
    let name: String
    let trace: RetainedBuildTestTrace
    var canAdopt = true
    var canComplete = true
    var acceptsAdoption = true
    var onWillAdopt: (() -> Void)?
    var onCommit: (() -> Void)?
    var onFinish: (() -> Void)?
    private var isAdopting = false
    private(set) var commitCount = 0
    private(set) var abandonCount = 0
    private(set) var finishCount = 0

    init(name: String, trace: RetainedBuildTestTrace) {
        self.name = name
        self.trace = trace
    }

    func supersede() {
        trace.record("\(name).supersede")
        if !isAdopting { canAdopt = false }
    }

    func willAdopt() -> Bool {
        trace.record("\(name).willAdopt")
        guard canAdopt, acceptsAdoption else { return false }
        isAdopting = true
        onWillAdopt?()
        return true
    }

    func commit() {
        commitCount += 1
        trace.record("\(name).commit")
        onCommit?()
    }

    func abandon() {
        abandonCount += 1
        trace.record("\(name).abandon")
    }

    func finishAfterCallbacks() {
        finishCount += 1
        trace.record("\(name).finish")
        onFinish?()
    }
}

@MainActor
private final class RetainedBuildTestLifecycle: RetainedBuildLifecycle {
    let trace: RetainedBuildTestTrace
    var rejectBegin = false
    var configure: ((RetainedBuildTestEpoch) -> Void)?
    var requestRevision: RetainedBuildTestRevision?
    private(set) var beginCount = 0
    private(set) var epochs: [RetainedBuildTestEpoch] = []
    private(set) var capturedRevisions: [Int] = []

    init(trace: RetainedBuildTestTrace) {
        self.trace = trace
    }

    func captureBuildRequest() -> (any RetainedBuildRequest)? {
        guard let requestRevision else { return nil }
        let value = requestRevision.value
        capturedRevisions.append(value)
        return RetainedBuildTestRequest(revision: requestRevision, capturedValue: value)
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        beginCount += 1
        let name = "root\(beginCount)"
        trace.record("\(name).begin")
        guard !rejectBegin else { return nil }
        let epoch = RetainedBuildTestEpoch(name: name, trace: trace)
        configure?(epoch)
        epochs.append(epoch)
        return epoch
    }
}

private enum RetainedBuildTestCompletionChange: CaseIterable, Equatable {
    case closeDuringAdoption
    case closeDuringCommit
    case closeDuringCleanup
    case closeDuringSharedCompletion
    case revisionDuringAdoption
}

private enum RetainedBuildTestReceiptInvalidation: CaseIterable, Equatable {
    case composition
    case nodeConstruction
    case preparation
}

@MainActor
private final class RetainedBuildTestRevision {
    var value = 0
}

@MainActor
private final class RetainedBuildTestRequest: RetainedBuildRequest {
    let revision: RetainedBuildTestRevision
    let capturedValue: Int

    init(revision: RetainedBuildTestRevision, capturedValue: Int) {
        self.revision = revision
        self.capturedValue = capturedValue
    }

    var isCurrent: Bool { revision.value == capturedValue }
}

@MainActor
private final class RetainedBuildTestSubtreeLease: RetainedSubtreeBuildLease {
    let trace: RetainedBuildTestTrace
    let name: String
    var canBuild = true
    var rejectBegin = false
    private(set) var beginCount = 0
    private(set) var epochs: [RetainedBuildTestEpoch] = []

    init(trace: RetainedBuildTestTrace, name: String = "geometry") {
        self.trace = trace
        self.name = name
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        beginCount += 1
        let epochName = "\(name)\(beginCount)"
        trace.record("\(epochName).begin")
        guard !rejectBegin else { return nil }
        let epoch = RetainedBuildTestEpoch(name: epochName, trace: trace)
        epochs.append(epoch)
        return epoch
    }
}

@MainActor
private final class RetainedBuildTestGeometry {
    let trace: RetainedBuildTestTrace
    let lease: RetainedBuildTestSubtreeLease
    var onBuild: ((RetainedViewRuntime, Size) -> Void)?
    private(set) var bodyCount = 0

    init(trace: RetainedBuildTestTrace, lease: RetainedBuildTestSubtreeLease) {
        self.trace = trace
        self.lease = lease
    }

    func makeNode(frameSize: Size, builtSize: Size, text: String = "seed") -> ViewNode {
        let node = retainedBuildTestNode("reader")
        node.frame = Rect(origin: .zero, size: frameSize)
        node.retainedSubtreeBuildLease = lease
        node.geometryReaderBuiltSize = builtSize
        node.addChild(retainedBuildTestNode("reader.content", text: text))
        node.geometryReaderBuild = { [self] runtime, slot in
            bodyCount += 1
            trace.record("geometry.body")
            onBuild?(runtime, slot)
            let candidate = makeNode(frameSize: slot, builtSize: slot, text: "built")
            trace.record("geometry.node")
            return [candidate]
        }
        return node
    }
}

@MainActor
private func retainedBuildTestNode(_ identity: String, text: String? = nil) -> ViewNode {
    let node = ViewNode(
        frame: Rect(x: 0, y: 0, width: 120, height: 80), backgroundColor: .white,
        text: text, isHitTestVisible: true)
    node.nodeTag = identity
    return node
}

@MainActor
private func retainedBuildTestRuntime() -> RetainedViewRuntime {
    RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 200), isHitTestVisible: false))
}

private func retainedBuildTestTransaction(animation: Animation?) -> Transaction {
    var transaction = Transaction(animation: animation)
    transaction.isContinuous = true
    transaction.scrollTargetAnchor = .trailing
    transaction.tracksVelocity = true
    return transaction
}

@MainActor
private func withRetainedBuildTestTransaction(_ transaction: Transaction?, _ body: () -> Void) {
    let previousTransaction = currentTransaction
    let previousAnimation = currentAnimationTransaction
    currentTransaction = transaction
    currentAnimationTransaction =
        transaction?.disablesAnimations == true ? nil : transaction?.animation.map { ($0.duration, $0.easing) }
    defer {
        currentTransaction = previousTransaction
        currentAnimationTransaction = previousAnimation
    }
    body()
}
