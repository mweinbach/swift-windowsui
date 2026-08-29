import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedTaskIDLifecycleTests: XCTestCase {
    func testInitialTaskWaitsForRenderAndSharedRenderPathsDoNotRepeatIt() async {
        let probe = MountedTaskIDLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(mountedTaskIDLifecycleLeaf(id: 1, label: "initial", version: "one", probe: probe))
        }
        defer { finish(host, probe: probe) }

        await assertNoActivity(probe) { host.reload() }
        XCTAssertTrue(probe.runs.isEmpty)
        let ready = expectReady(probe)
        host.render()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.version), ["one"])
        XCTAssertEqual(probe.suspendedCount, 1)

        await assertNoActivity(probe) {
            host.render()
            _ = host.runtime.renderFrame()
            host.render()
        }
        XCTAssertEqual(probe.runs.count, 1)
    }

    func testEqualIDsInTwoHostsKeepIndependentTasksAndCancellation() async {
        await assertIndependentHosts(firstID: 1, secondID: 1)
    }

    func testDifferentIDsInTwoHostsKeepIndependentTasksAndCancellation() async {
        await assertIndependentHosts(firstID: 1, secondID: 9)
    }

    func testReusingOneStatefulSourceForTwoSiblingsDoesNotAliasTheirTaskSlots() async throws {
        let probe = MountedTaskIDLifecycleProbe()
        let state = MountedTaskIDLifecycleBindings()
        let leaf = MountedTaskIDLifecycleStateLeaf(probe: probe, state: state)
        let host = MountedOnChangeTestHost {
            state.values.removeAll()
            return AnyView(
                HStack {
                    leaf
                    leaf
                })
        }
        defer { finish(host, probe: probe) }
        XCTAssertEqual(state.values.count, 2)
        let first = try XCTUnwrap(state.values.first)
        let second = try XCTUnwrap(state.values.last)
        let ready = expectReady(probe, count: 2)
        host.render()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.version), ["1", "1"])

        let restarted = expectReady(probe)
        let cancelled = expectCancellation(probe)
        first.wrappedValue = 2
        await fulfillment(of: [restarted, cancelled], timeout: 5)
        XCTAssertEqual(first.wrappedValue, 2)
        XCTAssertEqual(second.wrappedValue, 1)
        XCTAssertEqual(probe.runs.map(\.version), ["1", "1", "2"])
        XCTAssertEqual(probe.cancellations.count, 1)
        XCTAssertEqual(probe.suspendedCount, 2)
    }

    func testNestedTasksWithTheSameIDTypeShareANodeWithoutSharingTheCallsiteSlot() async throws {
        let probe = MountedTaskIDLifecycleProbe()
        var innerID = 1
        let host = MountedOnChangeTestHost {
            AnyView(
                mountedTaskIDLifecycleDecorate(
                    mountedTaskIDLifecycleDecorate(
                        Text("nested-same"), id: innerID, label: "inner", version: String(innerID), probe: probe),
                    id: 1, label: "outer", version: "outer-one", probe: probe))
        }
        defer { finish(host, probe: probe) }
        let node = try textNode("nested-same", in: host.runtime)
        let ready = expectReady(probe, count: 2)
        host.render()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(Set(probe.runs.map(\.label)), Set(["inner", "outer"]))
        XCTAssertEqual(nodes(in: host.runtime.root).filter { $0.text == "nested-same" }.count, 1)

        let restarted = expectReady(probe)
        let cancelled = expectCancellation(probe)
        innerID = 2
        host.reload()
        await fulfillment(of: [restarted, cancelled], timeout: 5)
        XCTAssertTrue(try textNode("nested-same", in: host.runtime) === node)
        XCTAssertEqual(probe.runs.last?.label, "inner")
        XCTAssertEqual(probe.runs.last?.version, "2")
        XCTAssertEqual(probe.cancelledRuns.map(\.label), ["inner"])
        XCTAssertEqual(probe.runs.filter { $0.label == "outer" }.count, 1)
    }

    func testNestedTasksWithDifferentIDTypesKeepIndependentAttempts() async {
        let probe = MountedTaskIDLifecycleProbe()
        var innerID = 1
        var outerID = "a"
        let host = MountedOnChangeTestHost {
            AnyView(
                mountedTaskIDLifecycleDecorate(
                    mountedTaskIDLifecycleDecorate(
                        Text("nested-different"), id: innerID, label: "inner", version: String(innerID), probe: probe),
                    id: outerID, label: "outer", version: outerID, probe: probe))
        }
        defer { finish(host, probe: probe) }
        let ready = expectReady(probe, count: 2)
        host.render()
        await fulfillment(of: [ready], timeout: 5)

        let innerReady = expectReady(probe)
        let innerCancelled = expectCancellation(probe)
        innerID = 2
        host.reload()
        await fulfillment(of: [innerReady, innerCancelled], timeout: 5)
        XCTAssertEqual(probe.cancelledRuns.map(\.label), ["inner"])
        let outerReady = expectReady(probe)
        let outerCancelled = expectCancellation(probe)
        outerID = "b"
        host.reload()
        await fulfillment(of: [outerReady, outerCancelled], timeout: 5)
        XCTAssertEqual(probe.cancelledRuns.map(\.label), ["inner", "outer"])
        XCTAssertEqual(probe.runs.filter { $0.label == "inner" }.map(\.version), ["1", "2"])
        XCTAssertEqual(probe.runs.filter { $0.label == "outer" }.map(\.version), ["a", "b"])
    }

    func testKeyedReorderKeepsTasksAndRemovalReinsertionCreatesOnlyTheDepartingAttempt() async throws {
        let probe = MountedTaskIDLifecycleProbe()
        var rows = [1, 2, 3]
        let host = MountedOnChangeTestHost {
            AnyView(
                VStack {
                    ForEach(rows, id: \.self) { row in
                        mountedTaskIDLifecycleLeaf(
                            id: row, label: "row-\(row)", version: String(row), probe: probe)
                    }
                })
        }
        defer { finish(host, probe: probe) }
        let first = try identifiedNode("row-1", in: host.runtime)
        let second = try identifiedNode("row-2", in: host.runtime)
        let third = try identifiedNode("row-3", in: host.runtime)
        let ready = expectReady(probe, count: 3)
        host.render()
        await fulfillment(of: [ready], timeout: 5)

        await assertNoActivity(probe) {
            rows = [3, 1, 2]
            host.reload()
            host.render()
        }
        XCTAssertTrue(try identifiedNode("row-1", in: host.runtime) === first)
        XCTAssertTrue(try identifiedNode("row-2", in: host.runtime) === second)
        XCTAssertTrue(try identifiedNode("row-3", in: host.runtime) === third)
        let cancelled = expectCancellation(probe)
        let completed = expectCompletion(probe)
        rows = [3, 1]
        host.reload()
        await fulfillment(of: [cancelled, completed], timeout: 5)
        XCTAssertEqual(probe.cancelledRuns.map(\.label), ["row-2"])
        XCTAssertEqual(probe.runs.count, 3)

        await assertNoActivity(probe) {
            rows = [2, 3, 1]
            host.reload()
        }
        XCTAssertFalse(try identifiedNode("row-2", in: host.runtime) === second)
        let reinserted = expectReady(probe)
        host.render()
        await fulfillment(of: [reinserted], timeout: 5)
        XCTAssertEqual(probe.runs.last?.label, "row-2")
        XCTAssertEqual(probe.runs.count, 4)
        XCTAssertEqual(probe.cancellations.count, 1)
    }

    func testExplicitIdentityValueAndTypeChangesCreateFreshMountedTasks() async throws {
        let probe = MountedTaskIDLifecycleProbe()
        var identity = 1
        var usesStringIdentity = false
        let leaf = mountedTaskIDLifecycleLeaf(id: 7, label: "explicit", version: "seven", probe: probe)
        let host = MountedOnChangeTestHost {
            if usesStringIdentity {
                return AnyView(leaf.id(String(identity)))
            }
            return AnyView(leaf.id(identity))
        }
        defer { finish(host, probe: probe) }
        var previous = try identifiedNode("explicit", in: host.runtime)
        let ready = expectReady(probe)
        host.render()
        await fulfillment(of: [ready], timeout: 5)

        for replacement in [(2, false), (2, true)] {
            let countBefore = probe.runs.count
            let cancelled = expectCancellation(probe)
            let completed = expectCompletion(probe)
            identity = replacement.0
            usesStringIdentity = replacement.1
            host.reload()
            await fulfillment(of: [cancelled, completed], timeout: 5)
            let replacementNode = try identifiedNode("explicit", in: host.runtime)
            XCTAssertFalse(replacementNode === previous)
            XCTAssertFalse(replacementNode.hasAppeared)
            await assertNoActivity(probe) {}
            XCTAssertEqual(probe.runs.count, countBefore)
            let appeared = expectReady(probe)
            host.render()
            await fulfillment(of: [appeared], timeout: 5)
            XCTAssertEqual(probe.runs.count, countBefore + 1)
            previous = replacementNode
        }
        XCTAssertEqual(probe.cancellations.count, 2)
    }

    func testOptionalNoneIsAnObservedIDAndCanRestartAfterASomeValue() async {
        let probe = MountedTaskIDLifecycleProbe()
        var identifier: Int?
        let host = MountedOnChangeTestHost {
            AnyView(
                mountedTaskIDLifecycleLeaf(
                    id: identifier, label: "optional", version: identifier.map(String.init) ?? "none", probe: probe))
        }
        defer { finish(host, probe: probe) }
        let initial = expectReady(probe)
        host.render()
        await fulfillment(of: [initial], timeout: 5)
        await assertNoActivity(probe) { host.reload() }

        let replacements: [Int?] = [4, nil]
        for replacement in replacements {
            let ready = expectReady(probe)
            let cancelled = expectCancellation(probe)
            identifier = replacement
            host.reload()
            await fulfillment(of: [ready, cancelled], timeout: 5)
        }
        XCTAssertEqual(probe.runs.map(\.version), ["none", "4", "none"])
        XCTAssertEqual(probe.cancellations.count, 2)
    }

    func testEqualityIgnoredPayloadKeepsThePriorIDBaselineAndLatestPendingAction() async {
        let probe = MountedTaskIDLifecycleProbe()
        var identifier = MountedTaskIDLifecycleComparedID(number: 1, payload: 10, probe: probe)
        var version = "first"
        let host = MountedOnChangeTestHost {
            AnyView(mountedTaskIDLifecycleLeaf(id: identifier, label: "compared", version: version, probe: probe))
        }
        defer { finish(host, probe: probe) }
        XCTAssertTrue(probe.comparisons.isEmpty)
        identifier = MountedTaskIDLifecycleComparedID(number: 1, payload: 20, probe: probe)
        version = "equal-pending"
        host.reload()
        XCTAssertEqual(probe.comparisons, [[1, 10, 1, 20]])
        let initial = expectReady(probe)
        host.render()
        await fulfillment(of: [initial], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.version), ["equal-pending"])

        await assertNoActivity(probe) {
            identifier = MountedTaskIDLifecycleComparedID(number: 1, payload: 30, probe: probe)
            version = "equal-running"
            host.reload()
        }
        let restarted = expectReady(probe)
        let cancelled = expectCancellation(probe)
        identifier = MountedTaskIDLifecycleComparedID(number: 2, payload: 40, probe: probe)
        version = "different"
        host.reload()
        await fulfillment(of: [restarted, cancelled], timeout: 5)
        XCTAssertEqual(probe.comparisons, [[1, 10, 1, 20], [1, 10, 1, 30], [1, 10, 2, 40]])
        XCTAssertEqual(probe.runs.map(\.version), ["equal-pending", "different"])
    }

    func testEqualIDBeforeFirstRenderUsesOnlyTheLatestActionAndPriority() async {
        let probe = MountedTaskIDLifecycleProbe()
        var version = "old"
        var priority = TaskPriority.background
        let host = MountedOnChangeTestHost {
            AnyView(
                mountedTaskIDLifecycleLeaf(
                    id: 1, label: "pending", version: version, probe: probe, priority: priority))
        }
        defer { finish(host, probe: probe) }
        await assertNoActivity(probe) {
            version = "latest"
            priority = .userInitiated
            host.reload()
        }
        let ready = expectReady(probe)
        host.render()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.version), ["latest"])
        XCTAssertEqual(probe.runs.first?.priority, .userInitiated)
        XCTAssertTrue(probe.cancellations.isEmpty)
    }

    func testEqualIDAfterCompletionDoesNotRestartForNewActionOrPriority() async {
        let probe = MountedTaskIDLifecycleProbe()
        var version = "finished"
        var priority = TaskPriority.userInitiated
        let host = MountedOnChangeTestHost {
            AnyView(
                mountedTaskIDLifecycleLeaf(
                    id: 1, label: "completed", version: version, probe: probe, priority: priority,
                    completesImmediately: true))
        }
        defer { finish(host, probe: probe) }
        let completed = expectCompletion(probe)
        host.render()
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertEqual(probe.runs.count, 1)
        XCTAssertEqual(probe.completions, [0])

        await assertNoActivity(probe) {
            version = "must-not-run"
            priority = .background
            host.reload()
            host.render()
        }
        XCTAssertEqual(probe.runs.map(\.version), ["finished"])
        XCTAssertEqual(probe.completions, [0])
    }

    func testChangedIDCancelsAndStartsOnTheRetainedNodeWithoutAnotherRender() async throws {
        let probe = MountedTaskIDLifecycleProbe()
        var identifier = 1
        let host = MountedOnChangeTestHost {
            AnyView(
                mountedTaskIDLifecycleLeaf(
                    id: identifier, label: "restart", version: String(identifier), probe: probe))
        }
        defer { finish(host, probe: probe) }
        let node = try identifiedNode("restart", in: host.runtime)
        let initial = expectReady(probe)
        host.render()
        await fulfillment(of: [initial], timeout: 5)
        let ready = expectReady(probe)
        let cancelled = expectCancellation(probe)
        let completed = expectCompletion(probe)

        identifier = 2
        host.reload()
        XCTAssertTrue(try identifiedNode("restart", in: host.runtime) === node)
        XCTAssertEqual(probe.cancellations, [0], "The installed handler runs synchronously inside replacement")
        await fulfillment(of: [ready, cancelled, completed], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.version), ["1", "2"])
        XCTAssertEqual(probe.completions, [0])
        XCTAssertEqual(probe.suspendedCount, 1)
    }

    func testAppearanceStateRebuildDefersTheTaskUntilOnlyTheLatestDeclarationCanRun() async throws {
        let probe = MountedTaskIDLifecycleProbe()
        let state = MountedTaskIDLifecycleBindings()
        let host = MountedOnChangeTestHost {
            AnyView(MountedTaskIDLifecycleAppearanceLeaf(probe: probe, state: state))
        }
        defer { finish(host, probe: probe) }
        let original = try textNode("appearance", in: host.runtime)
        await assertNoActivity(probe) { host.render() }
        XCTAssertEqual(state.values.last?.wrappedValue, 1)
        XCTAssertEqual(probe.appearances, 1)
        XCTAssertTrue(original.hasPendingAppearanceCallbacks)
        XCTAssertTrue(try textNode("appearance", in: host.runtime) === original)

        let ready = expectReady(probe)
        host.render()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.version), ["1"])
        XCTAssertEqual(probe.appearances, 1)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertFalse(original.hasPendingAppearanceCallbacks)
    }

    func testRemovingAndReaddingALogicalTaskKeepsThePhysicalNodeAndStartsWithoutAnotherAppearance() async throws {
        let probe = MountedTaskIDLifecycleProbe()
        let tasked = Text("logical-slot").task(id: 1) {
            await probe.run(label: "logical", version: "one")
        }
        let plain = Text("logical-slot").onAppear {}
        // Both public modifiers currently produce ModifiedView<Text>. The
        // erased choice is outside ViewBuilder, so it adds no branch identity.
        XCTAssertEqual(ObjectIdentifier(type(of: tasked)), ObjectIdentifier(type(of: plain)))
        var includesTask = true
        let host = MountedOnChangeTestHost { includesTask ? AnyView(tasked) : AnyView(plain) }
        defer { finish(host, probe: probe) }
        let original = try textNode("logical-slot", in: host.runtime)
        let initial = expectReady(probe)
        host.render()
        await fulfillment(of: [initial], timeout: 5)
        let cancelled = expectCancellation(probe)
        includesTask = false
        host.reload()
        await fulfillment(of: [cancelled], timeout: 5)
        XCTAssertTrue(try textNode("logical-slot", in: host.runtime) === original)
        XCTAssertTrue(original.hasAppeared)
        XCTAssertFalse(original.hasPendingAppearanceCallbacks)
        XCTAssertEqual(probe.cancellations, [0])

        let readded = expectReady(probe)
        includesTask = true
        host.reload()
        await fulfillment(of: [readded], timeout: 5)
        XCTAssertTrue(try textNode("logical-slot", in: host.runtime) === original)
        XCTAssertEqual(probe.runs.count, 2)
        XCTAssertEqual(probe.cancellations, [0])
        XCTAssertTrue(original.hasAppeared)
        XCTAssertFalse(original.hasPendingAppearanceCallbacks)
    }

    func testOutgoingOverlayCancelsAfterItsPhysicalDisappearanceCallback() async throws {
        let probe = MountedTaskIDLifecycleProbe()
        let clock = MountedTaskIDLifecycleClock()
        var visible = true
        let host = MountedOnChangeTestHost {
            AnyView(
                VStack {
                    if visible {
                        mountedTaskIDLifecycleLeaf(id: 1, label: "overlay", version: "one", probe: probe)
                            .onDisappear { probe.order.append("disappear") }
                            .transition(.opacity)
                    }
                })
        }
        defer { finish(host, probe: probe) }
        host.runtime.clock = { clock.now }
        let node = try identifiedNode("overlay", in: host.runtime)
        let ready = expectReady(probe)
        host.render()
        await fulfillment(of: [ready], timeout: 5)
        probe.onCancellation = { _ in probe.order.append("cancel") }
        await assertNoActivity(probe) {
            withAnimation(.linear(duration: 1)) {
                visible = false
                host.reload()
            }
        }
        XCTAssertTrue(host.runtime.transitionOverlays.contains { $0 === node })
        XCTAssertTrue(probe.order.isEmpty)
        let removal = try XCTUnwrap(node.animationStates[.opacity])
        XCTAssertEqual(removal.startTime, clock.now)
        XCTAssertEqual(removal.duration, 1)
        clock.now += 0.5
        _ = host.runtime.tickAnimations(at: clock.now)
        host.render()
        XCTAssertTrue(probe.order.isEmpty)
        XCTAssertEqual(node.opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(probe.suspendedCount, 1)

        let cancelled = expectCancellation(probe)
        let completed = expectCompletion(probe)
        clock.now += 1
        _ = host.runtime.tickAnimations(at: clock.now)
        host.render()
        await fulfillment(of: [cancelled, completed], timeout: 5)
        XCTAssertEqual(probe.order, ["disappear", "cancel"])
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(probe.runs.count, 1)
    }

    func testClosingAMountedHostCancelsOrdinaryAndIDTasksAfterStateRevocation() async throws {
        let probe = MountedTaskIDLifecycleProbe()
        let state = MountedTaskIDLifecycleBindings()
        let host = MountedOnChangeTestHost {
            AnyView(MountedTaskIDLifecycleMixedLeaf(probe: probe, state: state))
        }
        defer { finish(host, probe: probe) }
        let binding = try XCTUnwrap(state.values.last)
        let ready = expectReady(probe, count: 2)
        host.render()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(Set(probe.runs.map(\.label)), Set(["ordinary", "scoped"]))
        var cancellationValues: [Int] = []
        probe.onCancellation = { _ in
            binding.wrappedValue = 99
            cancellationValues.append(binding.wrappedValue)
        }
        let cancelled = expectCancellation(probe, count: 2)
        let completed = expectCompletion(probe, count: 2)
        host.close()
        XCTAssertEqual(cancellationValues, [7, 7])
        XCTAssertEqual(binding.wrappedValue, 7)
        XCTAssertEqual(host.coordinator.registry.liveOwnerCount, 0)
        await fulfillment(of: [cancelled, completed], timeout: 5)
        XCTAssertEqual(Set(probe.cancelledRuns.map(\.label)), Set(["ordinary", "scoped"]))
        XCTAssertEqual(probe.suspendedCount, 0)
    }

    func testUnmanagedIDTaskIsInactiveWhileOrdinaryTaskRetainsItsRawRuntimeLifetime() async {
        let probe = MountedTaskIDLifecycleProbe()
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300)))
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 300) }, invalidateHandler: {})
        var identifier = 1
        host.setComponents {
            [
                Text("unmanaged")
                    .task { await probe.run(label: "ordinary", version: "raw") }
                    .task(id: identifier) { await probe.run(label: "scoped", version: "must-not-run") }
                    .makeComponent(context: context)
            ]
        }
        defer {
            probe.clearAcknowledgements()
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            runtime.root.removeAllChildren()
            probe.releaseAll()
        }
        let ready = expectReady(probe)
        _ = runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.label), ["ordinary"])
        // This explicitly documents the intermediate unmanaged-ID limitation;
        // it is not evidence that the public snapshotter mounts ID tasks.
        await assertNoActivity(probe) {
            identifier = 2
            host.reload()
            _ = runtime.renderFrame()
        }
        XCTAssertEqual(probe.runs.map(\.label), ["ordinary"])
        let cancelled = expectCancellation(probe)
        let completed = expectCompletion(probe)
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
        await fulfillment(of: [cancelled, completed], timeout: 5)
        XCTAssertEqual(probe.cancelledRuns.map(\.label), ["ordinary"])
    }

    func testClosingBeforeFirstAppearanceDoesNotRunAnIDTask() async {
        let probe = MountedTaskIDLifecycleProbe()
        let host = MountedOnChangeTestHost {
            AnyView(mountedTaskIDLifecycleLeaf(id: 1, label: "closed-pending", version: "one", probe: probe))
        }
        defer { finish(host, probe: probe) }
        await assertNoActivity(probe) {
            host.close()
            _ = host.runtime.renderScene()
        }
        XCTAssertTrue(host.isClosed)
        XCTAssertTrue(probe.runs.isEmpty)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertTrue(probe.completions.isEmpty)
    }

    private func assertIndependentHosts(firstID: Int, secondID: Int) async {
        let firstProbe = MountedTaskIDLifecycleProbe()
        let secondProbe = MountedTaskIDLifecycleProbe()
        var firstValue = firstID
        let first = MountedOnChangeTestHost {
            AnyView(
                mountedTaskIDLifecycleLeaf(
                    id: firstValue, label: "shared-callsite", version: String(firstValue), probe: firstProbe))
        }
        let second = MountedOnChangeTestHost {
            AnyView(
                mountedTaskIDLifecycleLeaf(
                    id: secondID, label: "shared-callsite", version: String(secondID), probe: secondProbe))
        }
        defer {
            finish(first, probe: firstProbe)
            finish(second, probe: secondProbe)
        }
        let firstReady = expectReady(firstProbe)
        let secondReady = expectReady(secondProbe)
        first.render()
        second.render()
        await fulfillment(of: [firstReady, secondReady], timeout: 5)
        let restarted = expectReady(firstProbe)
        let cancelled = expectCancellation(firstProbe)
        firstValue += 100
        first.reload()
        await fulfillment(of: [restarted, cancelled], timeout: 5)
        await assertNoActivity(secondProbe) {
            second.reload()
            second.render()
        }
        XCTAssertEqual(firstProbe.runs.map(\.version), [String(firstID), String(firstID + 100)])
        XCTAssertEqual(firstProbe.cancellations, [0])
        XCTAssertEqual(secondProbe.runs.map(\.version), [String(secondID)])
        XCTAssertTrue(secondProbe.cancellations.isEmpty)
        XCTAssertEqual(secondProbe.suspendedCount, 1)
    }

    private func expectReady(_ probe: MountedTaskIDLifecycleProbe, count: Int = 1) -> XCTestExpectation {
        let result = expectation(description: "Task action entered with cancellation handler installed")
        result.expectedFulfillmentCount = count
        result.assertForOverFulfill = true
        probe.onReady = { _ in result.fulfill() }
        return result
    }

    private func expectCancellation(_ probe: MountedTaskIDLifecycleProbe, count: Int = 1) -> XCTestExpectation {
        let result = expectation(description: "Installed task cancellation handler ran")
        result.expectedFulfillmentCount = count
        result.assertForOverFulfill = true
        probe.onCancelled = { _ in result.fulfill() }
        return result
    }

    private func expectCompletion(_ probe: MountedTaskIDLifecycleProbe, count: Int = 1) -> XCTestExpectation {
        let result = expectation(description: "Acknowledged task action completed")
        result.expectedFulfillmentCount = count
        result.assertForOverFulfill = true
        probe.onCompleted = { _ in result.fulfill() }
        return result
    }

    private func assertNoActivity(_ probe: MountedTaskIDLifecycleProbe, action: () -> Void) async {
        let runs = probe.runs
        let cancellations = probe.cancellations
        let completions = probe.completions
        let unexpected = expectation(description: "No task activity in this negative-only observation window")
        unexpected.isInverted = true
        probe.onReady = { _ in unexpected.fulfill() }
        probe.onCancelled = { _ in unexpected.fulfill() }
        probe.onCompleted = { _ in unexpected.fulfill() }
        action()
        // This bounded inverted expectation is only a negative assertion.
        // Positive starts and installed handlers always have explicit receipts.
        await fulfillment(of: [unexpected], timeout: 0.05)
        probe.clearAcknowledgements()
        XCTAssertEqual(probe.runs, runs)
        XCTAssertEqual(probe.cancellations, cancellations)
        XCTAssertEqual(probe.completions, completions)
    }

    private func finish(_ host: MountedOnChangeTestHost, probe: MountedTaskIDLifecycleProbe) {
        probe.clearAcknowledgements()
        probe.onCancellation = nil
        host.close()
        probe.releaseAll()
    }

    private func identifiedNode(_ identifier: String, in runtime: RetainedViewRuntime) throws -> ViewNode {
        try XCTUnwrap(nodes(in: runtime.root).first { $0.accessibilityIdentifier == identifier })
    }

    private func textNode(_ text: String, in runtime: RetainedViewRuntime) throws -> ViewNode {
        try XCTUnwrap(nodes(in: runtime.root).first { $0.text == text })
    }

    private func nodes(in root: ViewNode) -> [ViewNode] {
        var result: [ViewNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }
}

private struct MountedTaskIDLifecycleRun: Equatable, Sendable {
    let number: Int
    let label: String
    let version: String
    let priority: TaskPriority
}

@MainActor
private final class MountedTaskIDLifecycleProbe {
    private(set) var runs: [MountedTaskIDLifecycleRun] = []
    private(set) var cancellations: [Int] = []
    private(set) var completions: [Int] = []
    var comparisons: [[Int]] = []
    var order: [String] = []
    var appearances = 0
    var onReady: ((MountedTaskIDLifecycleRun) -> Void)?
    var onCancelled: ((MountedTaskIDLifecycleRun) -> Void)?
    var onCompleted: ((MountedTaskIDLifecycleRun) -> Void)?
    var onCancellation: ((MountedTaskIDLifecycleRun) -> Void)?
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isReleased = false

    var suspendedCount: Int { continuations.count }
    var cancelledRuns: [MountedTaskIDLifecycleRun] { cancellations.map { runs[$0] } }

    func run(label: String, version: String, completesImmediately: Bool = false) async {
        let run = MountedTaskIDLifecycleRun(
            number: runs.count, label: label, version: version, priority: Task.currentPriority)
        runs.append(run)
        if completesImmediately {
            onReady?(run)
        } else {
            await withTaskCancellationHandler(
                operation: {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        if Task.isCancelled || cancellations.contains(run.number) {
                            cancel(run)
                            continuation.resume()
                        } else if isReleased {
                            continuation.resume()
                        } else {
                            continuations[run.number] = continuation
                        }
                        // The operation is inside the installed cancellation
                        // handler, and a live action has stored its suspension.
                        onReady?(run)
                    }
                },
                onCancel: { [weak self] in
                    // These tests cancel only through MainActor reload,
                    // disappearance, or owned-host close. Observe inline.
                    let probe = self
                    MainActor.assumeIsolated { probe?.cancel(run) }
                })
        }
        completions.append(run.number)
        onCompleted?(run)
    }

    private func cancel(_ run: MountedTaskIDLifecycleRun) {
        guard !cancellations.contains(run.number) else { return }
        cancellations.append(run.number)
        let continuation = continuations.removeValue(forKey: run.number)
        onCancellation?(run)
        onCancelled?(run)
        continuation?.resume()
    }

    func clearAcknowledgements() {
        onReady = nil
        onCancelled = nil
        onCompleted = nil
    }

    func releaseAll() {
        isReleased = true
        let pending = Array(continuations.values)
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@MainActor
private final class MountedTaskIDLifecycleBindings {
    var values: [Binding<Int>] = []
}

@MainActor
private final class MountedTaskIDLifecycleClock {
    var now: Double = 100
}

private struct MountedTaskIDLifecycleComparedID: Equatable {
    let number: Int
    let payload: Int
    let probe: MountedTaskIDLifecycleProbe

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.probe.comparisons.append([lhs.number, lhs.payload, rhs.number, rhs.payload])
            return lhs.number == rhs.number
        }
    }
}

@MainActor
private func mountedTaskIDLifecycleDecorate<Content: View, ID: Equatable>(
    _ content: Content, id: ID, label: String, version: String, probe: MountedTaskIDLifecycleProbe,
    priority: TaskPriority = .userInitiated, completesImmediately: Bool = false
) -> some View {
    // Every generic helper invocation has this same authored task callsite.
    content.task(id: id, priority: priority) {
        await probe.run(label: label, version: version, completesImmediately: completesImmediately)
    }
}

@MainActor
private func mountedTaskIDLifecycleLeaf<ID: Equatable>(
    id: ID, label: String, version: String, probe: MountedTaskIDLifecycleProbe,
    priority: TaskPriority = .userInitiated, completesImmediately: Bool = false
) -> some View {
    mountedTaskIDLifecycleDecorate(
        Color.blue.frame(width: 40, height: 24).accessibilityIdentifier(label),
        id: id, label: label, version: version, probe: probe,
        priority: priority, completesImmediately: completesImmediately)
}

@MainActor
private struct MountedTaskIDLifecycleStateLeaf: View {
    @State private var identifier = 1
    let probe: MountedTaskIDLifecycleProbe
    let state: MountedTaskIDLifecycleBindings

    var body: some View {
        state.values.append($identifier)
        return mountedTaskIDLifecycleLeaf(
            id: identifier, label: "reused", version: String(identifier), probe: probe)
    }
}

@MainActor
private struct MountedTaskIDLifecycleAppearanceLeaf: View {
    @State private var phase = 0
    let probe: MountedTaskIDLifecycleProbe
    let state: MountedTaskIDLifecycleBindings

    var body: some View {
        state.values.append($phase)
        let version = phase
        return mountedTaskIDLifecycleDecorate(
            Text("appearance").onAppear {
                probe.appearances += 1
                phase = 1
            },
            id: version, label: "appearance", version: String(version), probe: probe)
    }
}

@MainActor
private struct MountedTaskIDLifecycleMixedLeaf: View {
    @State private var identifier = 7
    let probe: MountedTaskIDLifecycleProbe
    let state: MountedTaskIDLifecycleBindings

    var body: some View {
        state.values.append($identifier)
        let version = identifier
        return Text("mixed")
            .task { await probe.run(label: "ordinary", version: "raw") }
            .task(id: version) { await probe.run(label: "scoped", version: String(version)) }
    }
}
