import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedTaskIDTransactionTests: XCTestCase {
    func testQueuedRootRestartPreservesFullTransactionAndRestoresOuterScope() async throws {
        for disablesAnimations in [false, true] {
            var transaction = detailedTransaction(animation: .linear(duration: 2))
            transaction.disablesAnimations = disablesAnimations
            try await assertQueuedRootRestart(scope: .full(transaction))
        }
    }

    func testQueuedRootRestartPreservesExplicitNilAnimation() async throws {
        let transaction = detailedTransaction(animation: nil)
        XCTAssertFalse(transaction.disablesAnimations)
        try await assertQueuedRootRestart(scope: .full(transaction))
    }

    func testQueuedRootRestartRetainsLegacyAnimationWithoutInventingAFullTransaction() async throws {
        try await assertQueuedRootRestart(scope: .legacy(3))
    }

    func testRootLogicalRemovalSweepUsesCapturedRequestBeforeImplicitNodeAnimation() async throws {
        for scope in sweepScopes() {
            try await assertLogicalRemovalSweep(scope: scope, inGeometryReader: false)
        }
    }

    func testGeometryRestartPreservesFullSubtreeTransactionOnTheRetainedTarget() async throws {
        for disablesAnimations in [false, true] {
            var transaction = detailedTransaction(animation: .linear(duration: 2))
            transaction.disablesAnimations = disablesAnimations
            try await assertGeometryRestart(scope: .full(transaction))
        }
    }

    func testGeometryRestartPreservesExplicitNilSubtreeTransaction() async throws {
        try await assertGeometryRestart(scope: .full(detailedTransaction(animation: nil)))
    }

    func testGeometryRestartRetainsLegacyAnimationWithoutInventingAFullTransaction() async throws {
        try await assertGeometryRestart(scope: .legacy(3))
    }

    func testGeometryLogicalRemovalSweepUsesSubtreeScopeBeforeImplicitNodeAnimation() async throws {
        for scope in sweepScopes() {
            try await assertLogicalRemovalSweep(scope: scope, inGeometryReader: true)
        }
    }

    func testFirstAppearanceUsesLaterRenderScopeWithoutLeakingItIntoTheAction() async throws {
        let probe = MountedTaskIDTransactionProbe()
        let buildScope = MountedTaskIDTransactionScope.full(detailedTransaction(animation: .linear(duration: 2)))
        let host = buildScope.perform { makeHost(probe: probe) }
        defer { finish(host, probe: probe) }
        let node = try taskNode(in: host)
        XCTAssertFalse(node.hasAppeared)
        XCTAssertTrue(probe.runs.isEmpty)
        XCTAssertTrue(probe.appearances.isEmpty)
        assertScope(probe.snapshot(), matches: .none)

        let noEarlyTask = expectation(description: "Construction has not admitted a task before render")
        noEarlyTask.isInverted = true
        probe.onReady = { _ in noEarlyTask.fulfill() }
        // The synchronous empty count alone cannot catch an eagerly queued
        // action. This bounded negative wait gives such a task an opportunity
        // to run before the renderer, without using yields as positive proof.
        await fulfillment(of: [noEarlyTask], timeout: 0.1)
        XCTAssertTrue(probe.runs.isEmpty)
        XCTAssertTrue(probe.appearances.isEmpty)

        let ready = expectReady(probe, value: 0)
        let renderScope = MountedTaskIDTransactionScope.full(detailedTransaction(animation: nil))
        let outer = outerScope()
        outer.perform {
            renderScope.perform {
                host.render()
                assertScope(probe.snapshot(), matches: renderScope)
            }
            assertScope(probe.snapshot(), matches: outer)
        }
        assertScope(probe.snapshot(), matches: .none)
        await fulfillment(of: [ready], timeout: 5)

        XCTAssertEqual(probe.appearances.count, 1)
        // This observes the appearance callback's synchronous scope. Task
        // creation itself has no application callback; its action runs later.
        assertScope(try XCTUnwrap(probe.appearances.first), matches: renderScope)
        XCTAssertFalse(try XCTUnwrap(probe.appearances.first).isBuilding)
        XCTAssertTrue(node.hasAppeared)
        XCTAssertEqual(probe.runs.map(\.value), [0])
        assertScope(try XCTUnwrap(probe.starts.first), matches: .none)
        XCTAssertFalse(try XCTUnwrap(probe.starts.first).isBuilding)
        XCTAssertEqual(probe.suspendedCount, 1)
    }

    func testPhysicalDisappearanceUsesTheLaterOverlayCompletionScope() async throws {
        let probe = MountedTaskIDTransactionProbe()
        var visible = true
        // Keep insertion immediate; the later removal owns the only tween.
        let buildScope = MountedTaskIDTransactionScope.full(detailedTransaction(animation: nil))
        let host = buildScope.perform {
            MountedOnChangeTestHost {
                AnyView(
                    VStack {
                        if visible {
                            mountedTaskIDTransactionLeaf(number: 0, probe: probe)
                                .transition(.opacity)
                        }
                    })
            }
        }
        probe.host = host
        host.runtime.clock = { probe.now }
        defer { finish(host, probe: probe) }
        let original = try taskNode(in: host)
        let ready = expectReady(probe, value: 0)
        host.render()
        await fulfillment(of: [ready], timeout: 5)
        probe.order.removeAll()

        let removalScope = MountedTaskIDTransactionScope.full(detailedTransaction(animation: .linear(duration: 1)))
        removalScope.perform {
            visible = false
            host.reload()
        }
        XCTAssertTrue(host.runtime.transitionOverlays.contains { $0 === original })
        XCTAssertTrue(probe.disappearances.isEmpty)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        XCTAssertEqual(original.animationStates[.opacity]?.duration, 1)

        let cancelled = expectCancellation(probe, value: 0)
        let completionScope = MountedTaskIDTransactionScope.legacy(7)
        let outer = outerScope()
        outer.perform {
            completionScope.perform {
                probe.now += 2
                _ = host.runtime.tickAnimations(at: probe.now)
                host.render()
                assertScope(probe.snapshot(), matches: completionScope)
            }
            assertScope(probe.snapshot(), matches: outer)
        }
        assertScope(probe.snapshot(), matches: .none)
        await fulfillment(of: [cancelled], timeout: 5)

        XCTAssertEqual(probe.order, ["disappear", "cancel:0"])
        XCTAssertEqual(probe.disappearances.count, 1)
        XCTAssertEqual(probe.cancellations.count, 1)
        assertScope(try XCTUnwrap(probe.disappearances.first), matches: completionScope)
        assertScope(try XCTUnwrap(probe.cancellations.first).snapshot, matches: completionScope)
        XCTAssertFalse(try XCTUnwrap(probe.disappearances.first).isBuilding)
        XCTAssertFalse(try XCTUnwrap(probe.cancellations.first).snapshot.isBuilding)
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(probe.runs.map(\.value), [0])
    }

    func testTerminalCloseUsesItsTriggeringScopeAndRestoresTheOuterTransaction() async throws {
        let probe = MountedTaskIDTransactionProbe()
        let buildScope = MountedTaskIDTransactionScope.full(detailedTransaction(animation: .linear(duration: 2)))
        let host = buildScope.perform { makeHost(probe: probe) }
        defer { finish(host, probe: probe) }
        let ready = expectReady(probe, value: 0)
        host.render()
        await fulfillment(of: [ready], timeout: 5)

        let cancelled = expectCancellation(probe, value: 0)
        let closeScope = MountedTaskIDTransactionScope.full(detailedTransaction(animation: nil))
        let outer = outerScope()
        outer.perform {
            closeScope.perform {
                host.close()
                assertScope(probe.snapshot(), matches: closeScope)
            }
            assertScope(probe.snapshot(), matches: outer)
        }
        assertScope(probe.snapshot(), matches: .none)
        await fulfillment(of: [cancelled], timeout: 5)

        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(probe.cancellations.count, 1)
        assertScope(try XCTUnwrap(probe.cancellations.first).snapshot, matches: closeScope)
        XCTAssertFalse(try XCTUnwrap(probe.cancellations.first).snapshot.isBuilding)
        XCTAssertEqual(probe.suspendedCount, 0)
        XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
        // This in-memory helper removes its children after the terminal task
        // drain. Those later physical removals invoke disappearance; they do
        // not establish the native window host's close callback policy.
        XCTAssertEqual(probe.order, ["appear", "cancel:0", "disappear"])
        assertScope(try XCTUnwrap(probe.disappearances.first), matches: closeScope)
        XCTAssertEqual(probe.runs.map(\.value), [0])
    }

    func testTaskResumptionDoesNotKeepLaunchOrResumerTransactionsAcrossAwait() async throws {
        let probe = MountedTaskIDTransactionProbe()
        let buildScope = MountedTaskIDTransactionScope.full(detailedTransaction(animation: .linear(duration: 2)))
        let host = buildScope.perform { makeHost(probe: probe) }
        defer { finish(host, probe: probe) }
        let ready = expectReady(probe, value: 0)
        outerScope().perform { host.render() }
        await fulfillment(of: [ready], timeout: 5)
        assertScope(try XCTUnwrap(probe.starts.first), matches: .none)
        XCTAssertFalse(try XCTUnwrap(probe.starts.first).isBuilding)
        XCTAssertEqual(probe.suspendedCount, 1)

        let completed = expectation(description: "The actual mounted task resumed and completed")
        completed.assertForOverFulfill = true
        probe.onCompleted = { run in
            XCTAssertEqual(run.value, 0)
            completed.fulfill()
        }
        let resumerScope = MountedTaskIDTransactionScope.legacy(5)
        resumerScope.perform {
            probe.releaseAll()
            assertScope(probe.snapshot(), matches: resumerScope)
        }
        assertScope(probe.snapshot(), matches: .none)
        await fulfillment(of: [completed], timeout: 5)

        XCTAssertEqual(probe.resumes.count, 1)
        assertScope(try XCTUnwrap(probe.resumes.first), matches: .none)
        XCTAssertFalse(try XCTUnwrap(probe.resumes.first).isBuilding)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.runs.map(\.value), [0])
        assertScope(probe.snapshot(), matches: .none)
    }

    private func assertQueuedRootRestart(scope: MountedTaskIDTransactionScope) async throws {
        let probe = MountedTaskIDTransactionProbe()
        let host = makeHost(probe: probe)
        defer { finish(host, probe: probe) }
        let original = try taskNode(in: host)
        let initial = expectReady(probe, value: 0)
        host.render()
        await fulfillment(of: [initial], timeout: 5)
        XCTAssertEqual(probe.suspendedCount, 1)
        probe.order.removeAll()
        probe.comparisons.removeAll()

        let restarted = expectReady(probe, value: 1)
        let cancelled = expectCancellation(probe, value: 0)
        let outer = outerScope()
        host.componentHost.onReloadCompleted = { [weak host, weak probe] in
            guard let host, let probe else { return }
            probe.recordCompletion()
            guard probe.completedRequests == 1 else { return }
            self.assertScope(probe.snapshot(), matches: outer)
            scope.perform {
                probe.number = 1
                probe.animationValue = 1
                host.reload()
                XCTAssertEqual(probe.comparisons.map(\.values), [[0, 0]])
                XCTAssertTrue(probe.cancellations.isEmpty, "The queued request has not adopted yet")
                self.assertScope(probe.snapshot(), matches: scope)
            }
            self.assertScope(probe.snapshot(), matches: outer)
        }
        outer.perform {
            host.reload()
            assertScope(probe.snapshot(), matches: outer)
        }
        assertScope(probe.snapshot(), matches: .none)

        XCTAssertEqual(probe.order, ["compare:0->0", "complete:1", "compare:0->1", "cancel:0", "complete:2"])
        XCTAssertEqual(probe.comparisons.map(\.values), [[0, 0], [0, 1]])
        XCTAssertEqual(probe.cancellations.count, 1)
        assertScope(try XCTUnwrap(probe.comparisons.last).snapshot, matches: scope)
        assertScope(try XCTUnwrap(probe.cancellations.first).snapshot, matches: scope)
        XCTAssertTrue(try XCTUnwrap(probe.comparisons.last).snapshot.isBuilding)
        XCTAssertTrue(try XCTUnwrap(probe.cancellations.first).snapshot.isBuilding)
        XCTAssertEqual(try XCTUnwrap(probe.cancellations.first).snapshot.completedRequests, 1)
        XCTAssertEqual(probe.completions.count, 2)
        assertScope(try XCTUnwrap(probe.completions.first), matches: outer)
        assertScope(try XCTUnwrap(probe.completions.last), matches: scope)
        XCTAssertTrue(try taskNode(in: host) === original)

        // An already-appeared target restarts at adopted delivery, without a
        // second render. Readiness acknowledges the installed handler, not a
        // chosen number of executor yields or the eventual final count.
        await fulfillment(of: [restarted, cancelled], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.value), [0, 1])
        XCTAssertEqual(probe.suspendedCount, 1)
        for snapshot in probe.starts {
            assertScope(snapshot, matches: .none)
            XCTAssertFalse(snapshot.isBuilding)
        }
        assertScope(probe.snapshot(), matches: .none)
    }

    private func assertGeometryRestart(scope: MountedTaskIDTransactionScope) async throws {
        let probe = MountedTaskIDTransactionProbe()
        let host = makeHost(probe: probe, inGeometryReader: true)
        defer { finish(host, probe: probe) }
        let initial = expectReady(probe, value: 400)
        host.render()
        await fulfillment(of: [initial], timeout: 5)
        let original = try taskNode(in: host)
        XCTAssertEqual(probe.suspendedCount, 1)
        probe.comparisons.removeAll()
        probe.order.removeAll()
        let priorResolves = host.runtime.geometryReaderResolveCount
        let rootConstructions = probe.rootConstructions
        let restarted = expectReady(probe, value: 500)
        let cancelled = expectCancellation(probe, value: 400)
        let outer = outerScope()

        outer.perform {
            // Hold existing terminal callback delivery across the inner
            // scope, so subtree finish must restore its captured transaction
            // rather than merely observe the query's immediate ambient one.
            // This is internal scheduling evidence, not native gesture order.
            host.runtime.beginLongPressReconciliation()
            scope.perform {
                probe.animationValue = 1
                host.runtime.root.frame = Rect(x: 0, y: 0, width: 500, height: 300)
                // A genuine layout query adopts the reader's changed subtree.
                // The target has appeared already; this is not a new frame or
                // evidence that the changed geometry has been presented.
                XCTAssertNotNil(host.runtime.resolvedLayoutFrame(of: host.runtime.root))
                assertScope(probe.snapshot(), matches: scope)
                XCTAssertTrue(probe.comparisons.isEmpty)
                XCTAssertTrue(probe.cancellations.isEmpty)
            }
            assertScope(probe.snapshot(), matches: outer)
            host.runtime.endLongPressReconciliation()
            assertScope(probe.snapshot(), matches: outer)
        }
        assertScope(probe.snapshot(), matches: .none)

        XCTAssertGreaterThan(host.runtime.geometryReaderResolveCount, priorResolves)
        XCTAssertEqual(probe.rootConstructions, rootConstructions)
        XCTAssertEqual(probe.completedRequests, 0, "This is a subtree adoption, not a root request")
        XCTAssertEqual(probe.comparisons.map(\.values), [[400, 500]])
        XCTAssertEqual(probe.order, ["compare:400->500", "cancel:400"])
        assertScope(try XCTUnwrap(probe.comparisons.first).snapshot, matches: scope)
        assertScope(try XCTUnwrap(probe.cancellations.first).snapshot, matches: scope)
        XCTAssertTrue(try XCTUnwrap(probe.comparisons.first).snapshot.isBuilding)
        XCTAssertTrue(try XCTUnwrap(probe.cancellations.first).snapshot.isBuilding)
        XCTAssertTrue(try taskNode(in: host) === original)
        await fulfillment(of: [restarted, cancelled], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.value), [400, 500])
        XCTAssertEqual(probe.suspendedCount, 1)
        assertScope(try XCTUnwrap(probe.starts.last), matches: .none)
        XCTAssertFalse(try XCTUnwrap(probe.starts.last).isBuilding)
        assertScope(probe.snapshot(), matches: .none)
    }

    private func assertLogicalRemovalSweep(
        scope: MountedTaskIDTransactionScope, inGeometryReader: Bool
    ) async throws {
        let probe = MountedTaskIDTransactionProbe()
        let host = makeHost(probe: probe, inGeometryReader: inGeometryReader)
        defer { finish(host, probe: probe) }
        let value = inGeometryReader ? 400 : 0
        let initial = expectReady(probe, value: value)
        host.render()
        await fulfillment(of: [initial], timeout: 5)
        let original = try taskNode(in: host)
        XCTAssertEqual(original.opacity, 1, accuracy: 0.0001)
        XCTAssertTrue(original.hasAppeared)
        XCTAssertEqual(probe.suspendedCount, 1)
        probe.order.removeAll()
        let cancelled = expectCancellation(probe, value: value)
        let outer = outerScope()

        if inGeometryReader {
            let rootConstructions = probe.rootConstructions
            let priorResolves = host.runtime.geometryReaderResolveCount
            outer.perform {
                host.runtime.beginLongPressReconciliation()
                scope.perform {
                    probe.includesTask = false
                    probe.animationValue = 1
                    host.runtime.root.frame = Rect(x: 0, y: 0, width: 500, height: 300)
                    XCTAssertNotNil(host.runtime.resolvedLayoutFrame(of: host.runtime.root))
                    assertScope(probe.snapshot(), matches: scope)
                    XCTAssertTrue(probe.cancellations.isEmpty, "The managed sweep is waiting behind retained callbacks")
                }
                assertScope(probe.snapshot(), matches: outer)
                host.runtime.endLongPressReconciliation()
                assertScope(probe.snapshot(), matches: outer)
            }
            XCTAssertEqual(probe.rootConstructions, rootConstructions)
            XCTAssertGreaterThan(host.runtime.geometryReaderResolveCount, priorResolves)
            XCTAssertEqual(probe.completedRequests, 0)
            XCTAssertEqual(probe.order, ["cancel:400"])
        } else {
            host.componentHost.onReloadCompleted = { [weak host, weak probe] in
                guard let host, let probe else { return }
                probe.recordCompletion()
                guard probe.completedRequests == 1 else { return }
                scope.perform {
                    probe.includesTask = false
                    probe.animationValue = 1
                    host.reload()
                    XCTAssertTrue(probe.cancellations.isEmpty)
                    self.assertScope(probe.snapshot(), matches: scope)
                }
                self.assertScope(probe.snapshot(), matches: outer)
            }
            outer.perform {
                host.reload()
                assertScope(probe.snapshot(), matches: outer)
            }
            XCTAssertEqual(probe.order, ["compare:0->0", "complete:1", "cancel:0", "complete:2"])
            XCTAssertEqual(try XCTUnwrap(probe.cancellations.first).snapshot.completedRequests, 1)
            assertScope(try XCTUnwrap(probe.completions.last), matches: scope)
        }
        assertScope(probe.snapshot(), matches: .none)
        XCTAssertTrue(try taskNode(in: host) === original, "This must exercise logical removal on a surviving node")
        XCTAssertTrue(original.hasAppeared)
        XCTAssertTrue(probe.disappearances.isEmpty, "Physical disappearance is not the sweep mechanism")
        XCTAssertEqual(probe.cancellations.count, 1)
        assertScope(try XCTUnwrap(probe.cancellations.first).snapshot, matches: scope)
        XCTAssertTrue(try XCTUnwrap(probe.cancellations.first).snapshot.isBuilding)
        if case .full(let transaction) = scope, transaction.disablesAnimations {
            XCTAssertNil(original.animationStates[.opacity])
            XCTAssertEqual(original.opacity, 0.25, accuracy: 0.0001)
        } else {
            // The opacity tween proves the node's implicit modifier did run.
            // Its nine-second scope must not replace the chosen sweep scope.
            XCTAssertEqual(original.animationStates[.opacity]?.duration, 9)
        }
        await fulfillment(of: [cancelled], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.value), [value])
        XCTAssertEqual(probe.suspendedCount, 0)
        assertScope(probe.snapshot(), matches: .none)
    }

    private func makeHost(
        probe: MountedTaskIDTransactionProbe, inGeometryReader: Bool = false
    ) -> MountedOnChangeTestHost {
        let host = MountedOnChangeTestHost {
            probe.rootConstructions += 1
            if inGeometryReader {
                return AnyView(
                    GeometryReader { proxy in
                        mountedTaskIDTransactionLeaf(number: Int(proxy.size.width), probe: probe)
                    })
            }
            return AnyView(mountedTaskIDTransactionLeaf(number: probe.number, probe: probe))
        }
        probe.host = host
        host.runtime.clock = { probe.now }
        host.componentHost.onReloadCompleted = { [weak probe] in probe?.recordCompletion() }
        XCTAssertNil(host.coordinator.latestInstallationError)
        return host
    }

    private func taskNode(in host: MountedOnChangeTestHost) throws -> ViewNode {
        var pending = [host.runtime.root]
        var matches: [ViewNode] = []
        while let node = pending.popLast() {
            if node.accessibilityIdentifier == "mounted-task-transaction" { matches.append(node) }
            pending.append(contentsOf: node.children)
        }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }

    private func expectReady(_ probe: MountedTaskIDTransactionProbe, value: Int) -> XCTestExpectation {
        let ready = expectation(description: "Task \(value) installed its cancellation handler and continuation")
        ready.assertForOverFulfill = true
        probe.onReady = { run in
            XCTAssertEqual(run.value, value)
            ready.fulfill()
        }
        return ready
    }

    private func expectCancellation(_ probe: MountedTaskIDTransactionProbe, value: Int) -> XCTestExpectation {
        let cancelled = expectation(description: "Task \(value) observed synchronous cancellation")
        cancelled.assertForOverFulfill = true
        probe.onCancelled = { run in
            XCTAssertEqual(run.value, value)
            cancelled.fulfill()
        }
        return cancelled
    }

    private func finish(_ host: MountedOnChangeTestHost, probe: MountedTaskIDTransactionProbe) {
        probe.onReady = nil
        probe.onCancelled = nil
        probe.onCompleted = nil
        host.componentHost.onReloadCompleted = nil
        host.close()
        probe.releaseAll()
    }

    private func outerScope() -> MountedTaskIDTransactionScope {
        var transaction = Transaction(animation: .linear(duration: 4))
        transaction.scrollTargetAnchor = .top
        return .full(transaction)
    }

    private func detailedTransaction(animation: Animation?) -> Transaction {
        var transaction = Transaction(animation: animation)
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .bottom
        transaction.tracksVelocity = true
        return transaction
    }

    private func sweepScopes() -> [MountedTaskIDTransactionScope] {
        var disabled = detailedTransaction(animation: .linear(duration: 2))
        disabled.disablesAnimations = true
        return [
            .full(detailedTransaction(animation: .linear(duration: 2))),
            .full(disabled),
            .full(detailedTransaction(animation: nil)),
            .legacy(3),
            .none,
        ]
    }

    private func assertScope(
        _ snapshot: MountedTaskIDTransactionSnapshot, matches scope: MountedTaskIDTransactionScope,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch scope {
        case .full(let transaction):
            XCTAssertNotNil(snapshot.transaction, file: file, line: line)
            XCTAssertEqual(
                snapshot.transaction?.animation?.duration, transaction.animation?.duration, file: file, line: line)
            XCTAssertEqual(
                snapshot.transaction?.animation?.easing, transaction.animation?.easing, file: file, line: line)
            XCTAssertEqual(
                snapshot.transaction?.disablesAnimations, transaction.disablesAnimations, file: file, line: line)
            XCTAssertEqual(snapshot.transaction?.isContinuous, transaction.isContinuous, file: file, line: line)
            XCTAssertEqual(
                snapshot.transaction?.scrollTargetAnchor, transaction.scrollTargetAnchor, file: file, line: line)
            XCTAssertEqual(snapshot.transaction?.tracksVelocity, transaction.tracksVelocity, file: file, line: line)
            let animation = transaction.disablesAnimations ? nil : transaction.animation
            XCTAssertEqual(snapshot.animationDuration, animation?.duration, file: file, line: line)
            XCTAssertEqual(snapshot.animationEasing, animation?.easing, file: file, line: line)
        case .legacy(let duration):
            XCTAssertNil(snapshot.transaction, file: file, line: line)
            XCTAssertEqual(snapshot.animationDuration, duration, file: file, line: line)
            XCTAssertEqual(snapshot.animationEasing, .linear, file: file, line: line)
        case .none:
            XCTAssertNil(snapshot.transaction, file: file, line: line)
            XCTAssertNil(snapshot.animationDuration, file: file, line: line)
            XCTAssertNil(snapshot.animationEasing, file: file, line: line)
        }
    }
}

@MainActor
private enum MountedTaskIDTransactionScope {
    case full(Transaction)
    case legacy(Double)
    case none

    func perform<Result>(_ body: () throws -> Result) rethrows -> Result {
        if case .full(let transaction) = self { return try withTransaction(transaction, body) }
        let previous = currentTransaction
        let previousAnimation = currentAnimationTransaction
        currentTransaction = nil
        if case .legacy(let duration) = self {
            currentAnimationTransaction = (duration: duration, easing: .linear)
        } else {
            currentAnimationTransaction = nil
        }
        defer {
            currentTransaction = previous
            currentAnimationTransaction = previousAnimation
        }
        return try body()
    }
}

private struct MountedTaskIDTransactionSnapshot {
    let transaction: Transaction?
    let animationDuration: Double?
    let animationEasing: AnimationEasing?
    let isBuilding: Bool
    let completedRequests: Int
}

private struct MountedTaskIDTransactionComparison {
    let values: [Int]
    let snapshot: MountedTaskIDTransactionSnapshot
}

private struct MountedTaskIDTransactionCancellation {
    let run: MountedTaskIDTransactionRun
    let snapshot: MountedTaskIDTransactionSnapshot
}

private struct MountedTaskIDTransactionRun: Sendable {
    let ordinal: Int
    let value: Int
}

private struct MountedTaskIDTransactionID: Equatable {
    let number: Int
    let probe: MountedTaskIDTransactionProbe

    static func == (lhs: Self, rhs: Self) -> Bool {
        // Mounted ID equality is synchronously called on MainActor. As in
        // the observer fixtures, this witness records that exact callback.
        MainActor.assumeIsolated {
            lhs.probe.comparisons.append(
                MountedTaskIDTransactionComparison(values: [lhs.number, rhs.number], snapshot: lhs.probe.snapshot()))
            lhs.probe.order.append("compare:\(lhs.number)->\(rhs.number)")
            return lhs.number == rhs.number
        }
    }
}

@MainActor
private final class MountedTaskIDTransactionProbe {
    var number = 0
    var animationValue = 0
    var includesTask = true
    var now = 100.0
    var rootConstructions = 0
    private(set) var completedRequests = 0
    var comparisons: [MountedTaskIDTransactionComparison] = []
    var order: [String] = []
    var appearances: [MountedTaskIDTransactionSnapshot] = []
    var disappearances: [MountedTaskIDTransactionSnapshot] = []
    private(set) var runs: [MountedTaskIDTransactionRun] = []
    private(set) var starts: [MountedTaskIDTransactionSnapshot] = []
    private(set) var resumes: [MountedTaskIDTransactionSnapshot] = []
    private(set) var cancellations: [MountedTaskIDTransactionCancellation] = []
    private(set) var completions: [MountedTaskIDTransactionSnapshot] = []
    var onReady: ((MountedTaskIDTransactionRun) -> Void)?
    var onCancelled: ((MountedTaskIDTransactionRun) -> Void)?
    var onCompleted: ((MountedTaskIDTransactionRun) -> Void)?
    weak var host: MountedOnChangeTestHost?
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isReleased = false

    var suspendedCount: Int { continuations.count }

    func snapshot() -> MountedTaskIDTransactionSnapshot {
        MountedTaskIDTransactionSnapshot(
            transaction: currentTransaction,
            animationDuration: currentAnimationTransaction?.duration,
            animationEasing: currentAnimationTransaction?.easing,
            isBuilding: host?.runtime.hasActiveRetainedBuild == true,
            completedRequests: completedRequests)
    }

    func recordCompletion() {
        completions.append(snapshot())
        completedRequests += 1
        order.append("complete:\(completedRequests)")
    }

    func run(number: Int) async {
        let run = MountedTaskIDTransactionRun(ordinal: runs.count, value: number)
        runs.append(run)
        starts.append(snapshot())
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if Task.isCancelled || cancellations.contains(where: { $0.run.ordinal == run.ordinal }) {
                    cancel(run)
                    continuation.resume()
                } else if isReleased {
                    continuation.resume()
                } else {
                    continuations[run.ordinal] = continuation
                }
                // Fulfillment occurs inside the installed handler and after
                // publishing its owned continuation. The test cancels only
                // after awaiting this per-generation acknowledgment.
                onReady?(run)
            }
        } onCancel: { [weak self] in
            // These fixtures cancel an acknowledged suspended task only via
            // a synchronous MainActor reload, disappearance, or owned close.
            let probe = self
            MainActor.assumeIsolated { probe?.cancel(run) }
        }
        resumes.append(snapshot())
        onCompleted?(run)
    }

    private func cancel(_ run: MountedTaskIDTransactionRun) {
        guard !cancellations.contains(where: { $0.run.ordinal == run.ordinal }) else { return }
        cancellations.append(MountedTaskIDTransactionCancellation(run: run, snapshot: snapshot()))
        order.append("cancel:\(run.value)")
        let continuation = continuations.removeValue(forKey: run.ordinal)
        onCancelled?(run)
        continuation?.resume()
    }

    func releaseAll() {
        isReleased = true
        let pending = Array(continuations.values)
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@MainActor
private func mountedTaskIDTransactionLeaf(
    number: Int, probe: MountedTaskIDTransactionProbe
) -> some View {
    let leaf = Color.blue
        .frame(width: 80, height: 24)
        .opacity(probe.animationValue == 0 ? 1 : 0.25)
        .accessibilityIdentifier("mounted-task-transaction")
    let tasked = leaf.task(id: MountedTaskIDTransactionID(number: number, probe: probe)) {
        await probe.run(number: number)
    }
    let plain = leaf.onAppear {}
    // Both alternatives are the same ModifiedView<Content> type. Erasing
    // outside ViewBuilder does not add a conditional identity or remove the
    // physical node when only its logical task declaration goes away.
    let content = probe.includesTask ? AnyView(tasked) : AnyView(plain)
    return
        content
        .onAppear {
            probe.appearances.append(probe.snapshot())
            probe.order.append("appear")
        }
        .onDisappear {
            probe.disappearances.append(probe.snapshot())
            probe.order.append("disappear")
        }
        .animation(.linear(duration: 9), value: probe.animationValue)
}
