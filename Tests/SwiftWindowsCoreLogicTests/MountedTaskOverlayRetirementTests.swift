import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedTaskOverlayRetirementTests: XCTestCase {
    func testOutgoingTaskCancellationUsesTheAmbientCompletionScopeAndRestoresItsCaller() async throws {
        var disabled = detailedTransaction(animation: .linear(duration: 3))
        disabled.disablesAnimations = true
        let scopes: [MountedTaskOverlayScope] = [
            .full(detailedTransaction(animation: nil)), .full(disabled), .legacy(7), .none,
        ]
        for completionScope in scopes {
            let probe = MountedTaskOverlayProbe()
            let host = singleHost(probe)
            defer { finish(host, probe: probe) }
            let original = try taskNode("overlay", in: host.runtime)
            await renderAndAcknowledge(host, probe: probe)

            beginFade(host, probe: probe)
            XCTAssertTrue(host.runtime.transitionOverlays.contains { $0 === original })
            XCTAssertTrue(probe.cancellations.isEmpty)
            XCTAssertTrue(probe.disappearances.isEmpty)
            XCTAssertEqual(probe.suspendedCount, 1)
            XCTAssertEqual(original.animationStates[.opacity]?.duration, 1)
            advance(host, probe: probe, by: 0.5)
            XCTAssertEqual(original.opacity, 0.5, accuracy: 0.0001)
            XCTAssertTrue(probe.order.isEmpty)

            let terminal = expectTerminal(probe, ordinals: [0])
            var outerTransaction = Transaction(animation: .linear(duration: 4))
            outerTransaction.scrollTargetAnchor = .top
            let outer = MountedTaskOverlayScope.full(outerTransaction)
            outer.perform {
                completionScope.perform {
                    advance(host, probe: probe, by: 1)
                    assertScope(probe.snapshot(), matches: completionScope)
                }
                assertScope(probe.snapshot(), matches: outer)
            }
            assertScope(probe.snapshot(), matches: .none)
            await fulfillment(of: terminal, timeout: 5)

            XCTAssertEqual(probe.order, ["disappear:overlay:0", "cancel:overlay:0"])
            let disappearance = try XCTUnwrap(probe.disappearances.first)
            let cancellation = try XCTUnwrap(probe.cancellations.first)
            assertScope(disappearance, matches: completionScope)
            assertScope(cancellation.snapshot, matches: completionScope)
            XCTAssertFalse(disappearance.isBuilding)
            XCTAssertFalse(cancellation.snapshot.isBuilding)
            XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
            assertFinishedExactlyOnce(probe, ordinal: 0)
        }
    }

    func testMidpointCloseCancelsTheOutgoingAttemptOnceWithoutSynthesizingDisappearance() async throws {
        let probe = MountedTaskOverlayProbe()
        let host = singleHost(probe)
        defer { finish(host, probe: probe) }
        let original = try taskNode("overlay", in: host.runtime)
        await renderAndAcknowledge(host, probe: probe)
        beginFade(host, probe: probe)
        advance(host, probe: probe, by: 0.5)
        XCTAssertEqual(original.opacity, 0.5, accuracy: 0.0001)
        XCTAssertTrue(host.runtime.transitionOverlays.contains { $0 === original })
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertTrue(probe.disappearances.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)

        let terminal = expectTerminal(probe, ordinals: [0])
        let closeScope = MountedTaskOverlayScope.full(detailedTransaction(animation: nil))
        closeScope.perform { host.close() }
        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(probe.order, ["cancel:overlay:0"])
        XCTAssertTrue(probe.disappearances.isEmpty)
        assertScope(try XCTUnwrap(probe.cancellations.first).snapshot, matches: closeScope)
        await fulfillment(of: terminal, timeout: 5)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        XCTAssertEqual(probe.suspendedCount, 0)

        // Terminal task cleanup does not redefine the existing visual lifetime.
        // A later explicit tick may deliver physical disappearance, but cannot
        // cancel or complete the already consumed attempt a second time.
        host.close()
        host.runtime.cancelRenderLifecycleTasks()
        advance(host, probe: probe, by: 2)
        _ = host.runtime.renderFrame()
        assertFinishedExactlyOnce(probe, ordinal: 0)
        XCTAssertEqual(probe.runs.count, 1)
    }

    func testCloseReentryFromTheRemovalClockDrainsTheAlreadyClaimedAttemptBeforeReturning() async throws {
        let probe = MountedTaskOverlayProbe()
        let host = singleHost(probe)
        defer { finish(host, probe: probe) }
        let original = try taskNode("overlay", in: host.runtime)
        await renderAndAcknowledge(host, probe: probe)
        let terminal = expectTerminal(probe, ordinals: [0])
        var enteredRemoval = false
        var closedFromClock = false
        let closeScope = MountedTaskOverlayScope.legacy(9)
        original.onDismantlePlatformView = { _ in enteredRemoval = true }
        host.runtime.clock = { [weak host] in
            guard let host, enteredRemoval, !closedFromClock else { return probe.now }
            closedFromClock = true
            // setChildren has removed the old child from the reachable tree,
            // but applyRemovalTransition has not admitted its overlay yet.
            XCTAssertFalse(self.nodes(in: host.runtime.root).contains { $0 === original })
            XCTAssertFalse(host.runtime.transitionOverlays.contains { $0 === original })
            XCTAssertTrue(probe.cancellations.isEmpty)
            closeScope.perform {
                host.close()
                XCTAssertEqual(probe.cancellations.map { $0.run.ordinal }, [0])
                XCTAssertEqual(probe.cancellationHandlerCalls, [0])
                XCTAssertEqual(probe.suspendedCount, 0)
                XCTAssertTrue(probe.disappearances.isEmpty)
                self.assertScope(probe.snapshot(), matches: closeScope)
            }
            return probe.now
        }

        beginFade(host, probe: probe)
        XCTAssertTrue(enteredRemoval)
        XCTAssertTrue(closedFromClock, "The test must close inside removal transition setup")
        XCTAssertTrue(host.isClosed)
        await fulfillment(of: terminal, timeout: 5)
        assertScope(try XCTUnwrap(probe.cancellations.first).snapshot, matches: closeScope)
        host.runtime.cancelRenderLifecycleTasks()
        assertFinishedExactlyOnce(probe, ordinal: 0)
        XCTAssertEqual(probe.runs.count, 1)
    }

    func testSameCallsiteReinsertionKeepsTheNewAttemptAliveWhenTheOldOverlayCompletes() async throws {
        let probe = MountedTaskOverlayProbe()
        let host = singleHost(probe)
        defer { finish(host, probe: probe) }
        let original = try taskNode("overlay", in: host.runtime)
        await renderAndAcknowledge(host, probe: probe)
        beginFade(host, probe: probe)
        advance(host, probe: probe, by: 0.5)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)

        probe.isVisible = true
        probe.generation = 1
        withTransaction(Transaction(animation: nil)) { host.reload() }
        let replacement = try taskNode("overlay", in: host.runtime)
        XCTAssertFalse(replacement === original)
        XCTAssertTrue(host.runtime.transitionOverlays.contains { $0 === original })
        await renderAndAcknowledge(host, probe: probe)
        XCTAssertEqual(probe.runs.map(\.generation), [0, 1])
        XCTAssertEqual(probe.suspendedCount, 2)

        let oldTerminal = expectTerminal(probe, ordinals: [0])
        advance(host, probe: probe, by: 1)
        await fulfillment(of: oldTerminal, timeout: 5)
        XCTAssertEqual(probe.order, ["disappear:overlay:0", "cancel:overlay:0"])
        XCTAssertEqual(probe.cancellations.map { $0.run.ordinal }, [0])
        XCTAssertEqual(probe.completions, [0])
        XCTAssertEqual(probe.suspendedCount, 1)
        XCTAssertTrue(replacement.hasAppeared)
        XCTAssertTrue(try taskNode("overlay", in: host.runtime) === replacement)
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)

        let newTerminal = expectTerminal(probe, ordinals: [1])
        host.close()
        await fulfillment(of: newTerminal, timeout: 5)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        assertFinishedExactlyOnce(probe, ordinal: 1)
        XCTAssertEqual(probe.suspendedCount, 0)
    }

    func testNestedTickFromDisappearanceCannotCompleteTheSameOverlayTwice() async throws {
        let probe = MountedTaskOverlayProbe()
        let host = singleHost(probe)
        defer { finish(host, probe: probe) }
        let original = try taskNode("overlay", in: host.runtime)
        await renderAndAcknowledge(host, probe: probe)
        let originalDisappear = try XCTUnwrap(original.onDisappear)
        var didReenter = false
        var callbackOrder: [String] = []
        original.onDisappear = { [weak host] in
            callbackOrder.append("enter")
            originalDisappear()
            if !didReenter {
                didReenter = true
                _ = host?.runtime.tickAnimations(at: probe.now)
                XCTAssertEqual(probe.disappearances.count, 1)
                XCTAssertTrue(probe.cancellations.isEmpty, "The outer disappearance callback has not returned")
            }
            callbackOrder.append("leave")
        }
        beginFade(host, probe: probe)
        let terminal = expectTerminal(probe, ordinals: [0])

        advance(host, probe: probe, by: 1.25)
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertTrue(didReenter)
        XCTAssertEqual(callbackOrder, ["enter", "leave"])
        XCTAssertEqual(probe.order, ["disappear:overlay:0", "cancel:overlay:0"])
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
        assertFinishedExactlyOnce(probe, ordinal: 0)
    }

    func testCloseFromDisappearanceDrainsItsInFlightTaskBeforeReturningToTheCallback() async throws {
        let probe = MountedTaskOverlayProbe()
        let host = singleHost(probe)
        defer { finish(host, probe: probe) }
        let original = try taskNode("overlay", in: host.runtime)
        await renderAndAcknowledge(host, probe: probe)
        let originalDisappear = try XCTUnwrap(original.onDisappear)
        let completionScope = MountedTaskOverlayScope.legacy(7)
        let closeScope = MountedTaskOverlayScope.full(detailedTransaction(animation: nil))
        var closedFromDisappearance = false
        original.onDisappear = { [weak host] in
            originalDisappear()
            XCTAssertFalse(closedFromDisappearance)
            closedFromDisappearance = true
            self.assertScope(probe.snapshot(), matches: completionScope)
            closeScope.perform {
                host?.close()
                XCTAssertEqual(probe.cancellations.map { $0.run.ordinal }, [0])
                XCTAssertEqual(probe.cancellationHandlerCalls, [0])
                XCTAssertEqual(probe.suspendedCount, 0)
                XCTAssertEqual(probe.disappearances.count, 1)
                self.assertScope(probe.snapshot(), matches: closeScope)
            }
            self.assertScope(probe.snapshot(), matches: completionScope)
        }
        beginFade(host, probe: probe)
        let terminal = expectTerminal(probe, ordinals: [0])

        completionScope.perform { advance(host, probe: probe, by: 1.25) }
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertTrue(closedFromDisappearance)
        XCTAssertTrue(host.isClosed)
        XCTAssertEqual(probe.order, ["disappear:overlay:0", "cancel:overlay:0"])
        XCTAssertEqual(probe.disappearances.count, 1)
        assertScope(try XCTUnwrap(probe.cancellations.first).snapshot, matches: closeScope)
        assertScope(probe.snapshot(), matches: .none)
        host.runtime.cancelRenderLifecycleTasks()
        assertFinishedExactlyOnce(probe, ordinal: 0)
    }

    func testUnrelatedImmediateAndAnimatedGroupsKeepIndependentCancellationBoundaries() async throws {
        let probe = MountedTaskOverlayProbe()
        let host = withTransaction(Transaction(animation: nil)) {
            MountedOnChangeTestHost {
                AnyView(
                    VStack {
                        if probe.isVisible {
                            mountedTaskOverlayLeaf(label: "animated", generation: 0, probe: probe)
                                .transition(.opacity)
                        }
                        if probe.isVisible {
                            mountedTaskOverlayLeaf(label: "immediate", generation: 0, probe: probe)
                        }
                    })
            }
        }
        configure(host, probe: probe)
        defer { finish(host, probe: probe) }
        let animated = try taskNode("animated", in: host.runtime)
        let immediate = try taskNode("immediate", in: host.runtime)
        await renderAndAcknowledge(host, probe: probe, count: 2)
        let immediateRun = try XCTUnwrap(probe.runs.first { $0.label == "immediate" })
        let animatedRun = try XCTUnwrap(probe.runs.first { $0.label == "animated" })
        let immediateTerminal = expectTerminal(probe, ordinals: [immediateRun.ordinal])

        beginFade(host, probe: probe)
        await fulfillment(of: immediateTerminal, timeout: 5)
        XCTAssertEqual(probe.order, ["disappear:immediate:0", "cancel:immediate:0"])
        XCTAssertEqual(probe.cancellations.map { $0.run.label }, ["immediate"])
        XCTAssertEqual(probe.suspendedCount, 1)
        XCTAssertTrue(host.runtime.transitionOverlays.contains { $0 === animated })
        XCTAssertFalse(host.runtime.transitionOverlays.contains { $0 === immediate })
        advance(host, probe: probe, by: 0.5)
        XCTAssertEqual(animated.opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(probe.cancellations.count, 1)

        let animatedTerminal = expectTerminal(probe, ordinals: [animatedRun.ordinal])
        advance(host, probe: probe, by: 1)
        await fulfillment(of: animatedTerminal, timeout: 5)
        XCTAssertEqual(
            probe.order,
            ["disappear:immediate:0", "cancel:immediate:0", "disappear:animated:0", "cancel:animated:0"])
        assertFinishedExactlyOnce(probe, ordinal: immediateRun.ordinal)
        assertFinishedExactlyOnce(probe, ordinal: animatedRun.ordinal)
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
    }

    func testRawRemoveChildKeepsItsTaskUntilTheOutgoingOverlayDisappears() async throws {
        try await assertRawRemoval(.removeChild)
    }

    func testRawReplaceChildKeepsItsTaskUntilTheOutgoingOverlayDisappears() async throws {
        try await assertRawRemoval(.replaceChild)
    }

    func testRawRemoveAllChildrenKeepsItsTaskUntilTheOutgoingOverlayDisappears() async throws {
        try await assertRawRemoval(.removeAllChildren)
    }

    func testCanvasSymbolLayoutDiscardCancelsAnOutstandingOverlayReceiptWithoutDisappearance() async throws {
        let probe = MountedTaskOverlayProbe()
        let host = singleHost(probe)
        defer { finish(host, probe: probe) }
        let original = try taskNode("overlay", in: host.runtime)
        await renderAndAcknowledge(host, probe: probe)
        beginFade(host, probe: probe)
        advance(host, probe: probe, by: 0.5)
        XCTAssertTrue(host.runtime.transitionOverlays.contains { $0 === original })
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        let terminal = expectTerminal(probe, ordinals: [0])
        let symbol = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 24))

        withTransaction(Transaction(animation: nil)) {
            XCTAssertNotNil(host.runtime.prepareCanvasSymbolLayout(content: symbol))
        }
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
        XCTAssertTrue(probe.disappearances.isEmpty)
        XCTAssertEqual(probe.order, ["cancel:overlay:0"])
        await fulfillment(of: terminal, timeout: 5)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        XCTAssertEqual(probe.suspendedCount, 0)

        XCTAssertNotNil(host.runtime.prepareCanvasSymbolLayout(content: symbol))
        advance(host, probe: probe, by: 2)
        host.close()
        assertFinishedExactlyOnce(probe, ordinal: 0)
        XCTAssertTrue(probe.disappearances.isEmpty)
    }

    func testStaleRemovalSetupCannotCaptureTheTaskInstalledByClockReentry() async throws {
        let probe = MountedTaskOverlayProbe()
        let fixture = MountedTaskOverlayGroupFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let sourceParent = fixture.members[0]
        let destination = fixture.members[1]
        let reused = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 20), text: "reused child")
        sourceParent.addChild(reused)
        var oldDisappearances = 0
        reused.onDisappear = { oldDisappearances += 1 }
        _ = fixture.runtime.renderScene()
        XCTAssertTrue(reused.hasAppeared)
        XCTAssertTrue(probe.runs.isEmpty, "The outgoing setup has no Task to transfer")
        reused.transition = RetainedTransition(kind: .opacity)
        var didReenter = false
        var replacement: RetainedTaskDeclaration?
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture, !didReenter else { return probe.now }
            didReenter = true
            XCTAssertEqual(currentAnimationTransaction?.duration, 1)
            XCTAssertTrue(reused.parent === sourceParent)
            XCTAssertTrue(sourceParent.children.contains { $0 === reused })
            let originalSetup = reused.captureLazyListAttachmentProof()
            XCTAssertTrue(originalSetup.isCurrent)
            reused.transition = .identity
            withTransaction(Transaction(animation: nil)) {
                // removeAllChildren still exposes the old child in its table.
                // This nested immediate removal therefore completes the old
                // lifetime before addChild establishes the later attachment.
                destination.addChild(reused)
                XCTAssertEqual(oldDisappearances, 1)
                XCTAssertTrue(reused.parent === destination)
                XCTAssertTrue(destination.children.contains { $0 === reused })
                XCTAssertFalse(originalSetup.isCurrent)
                XCTAssertTrue(reused.captureLazyListAttachmentProof().isCurrent)
                reused.onDisappear = { probe.recordDisappearance(label: "replacement", generation: 1) }
                do {
                    let next = try fixture.installGroup(
                        probe: probe, targets: [reused], label: "replacement", generation: 1)
                    replacement = next
                    XCTAssertTrue(next.canCommit)
                    next.deliver(restart: false)
                    _ = fixture.runtime.renderScene()
                    XCTAssertTrue(reused.hasAppeared)
                    XCTAssertFalse(reused.hasPendingAppearanceCallbacks)
                } catch {
                    XCTFail("The replacement Task must complete native adoption: \(error)")
                }
            }
            reused.transition = RetainedTransition(kind: .opacity)
            return probe.now
        }
        let ready = expectReady(probe)

        withAnimation(.linear(duration: 1)) { sourceParent.removeAllChildren() }
        XCTAssertTrue(didReenter)
        XCTAssertNotNil(replacement)
        XCTAssertEqual(oldDisappearances, 1)
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.label), ["replacement"])
        XCTAssertEqual(probe.runs.map(\.generation), [1])
        XCTAssertTrue(probe.disappearances.isEmpty)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        XCTAssertTrue(fixture.runtime.transitionOverlays.contains { $0 === reused })

        // The older generic remover can still overwrite parent/runtime after
        // the callback. This test does not claim that attachment is preserved.
        // Do not repair, reattach, or render here: another attachment write
        // would invalidate even an incorrectly refreshed overlay entry.
        probe.now += 1.25
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(oldDisappearances, 1)
        XCTAssertTrue(probe.disappearances.isEmpty)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        let terminal = expectTerminal(probe, ordinals: [0])

        fixture.close()
        await fulfillment(of: terminal, timeout: 5)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        XCTAssertEqual(oldDisappearances, 1)
    }

    func testOwnedAdapterDetachPreservesTheOutgoingTaskAndPhysicalDisappearance() async throws {
        let probe = MountedTaskOverlayProbe()
        let fixture = MountedTaskOverlayGroupFixture(probe: probe)
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        defer {
            fixture.finish(probe: probe)
            provider.close()
        }
        let container = fixture.members[0]
        let descendant = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 20), text: "adapter row")
        container.addChild(descendant)
        XCTAssertTrue(provider.replaceData([0], id: \.self, rowContent: { _ in [descendant] }))
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 40, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let declaration = try fixture.installGroup(probe: probe, targets: [container], label: "adapter")
        let ready = expectReady(probe)
        declaration.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertTrue(container.hasAppeared)
        // Attach the raw adapter only after task readiness; no intervening
        // render performs checked row adoption before the removal under test.
        container.retainedSubtreeBuildLease = MountedTaskOverlayAdapterLease()
        container.retainedLazyListAdapter = adapter
        XCTAssertTrue(adapter.ownsAttachment(container))
        container.transition = RetainedTransition(kind: .opacity)

        withAnimation(.linear(duration: 1)) { fixture.runtime.root.removeChild(container) }
        // This owned adapter takes setRuntime's special native detach branch,
        // whose gate and Task-state invalidation must not lose the accepted
        // overlay's eventual physical callback or its original task receipt.
        XCTAssertFalse(adapter.ownsAttachment(container))
        XCTAssertFalse(declaration.canCommit)
        XCTAssertTrue(fixture.runtime.transitionOverlays.contains { $0 === container })
        XCTAssertTrue(probe.order.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        probe.now += 0.5
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertEqual(container.opacity, 0.5, accuracy: 0.0001)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertTrue(probe.disappearances.isEmpty)
        let terminal = expectTerminal(probe, ordinals: [0])

        probe.now += 1
        _ = fixture.runtime.tickAnimations(at: probe.now)
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "cancel:adapter:0"])
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        assertFinishedExactlyOnce(probe, ordinal: 0)
    }

    func testOneTaskGroupWaitsForEveryOutgoingRootRegardlessOfClaimAndCompletionOrder() async throws {
        // The forest claim visits roots in reverse order; admission visits them
        // in forward order. Both duration orders reject attaching a whole-group
        // obligation to just the first visited or first admitted root.
        for durations in [[1.0, 2.0], [2.0, 1.0]] {
            let probe = MountedTaskOverlayProbe()
            let fixture = MountedTaskOverlayGroupFixture(probe: probe)
            defer { fixture.finish(probe: probe) }
            let declaration = try fixture.installGroup(probe: probe)
            let ready = expectReady(probe)
            declaration.deliver(restart: false)
            _ = fixture.runtime.renderScene()
            await fulfillment(of: [ready], timeout: 5)
            XCTAssertEqual(probe.suspendedCount, 1)
            XCTAssertTrue(declaration.canCommit)
            let first = durations[0] < durations[1] ? 0 : 1
            let last = 1 - first
            fixture.beginFade(durations: durations)
            XCTAssertTrue(fixture.runtime.root.children.isEmpty)
            XCTAssertEqual(fixture.runtime.transitionOverlays.count, 2)
            XCTAssertTrue(
                fixture.members.allSatisfy { member in
                    fixture.runtime.transitionOverlays.contains { $0 === member }
                })
            XCTAssertFalse(declaration.canCommit)
            XCTAssertTrue(probe.order.isEmpty)

            probe.now += 1.25
            _ = fixture.runtime.tickAnimations(at: probe.now)
            XCTAssertEqual(probe.order, ["disappear:root-\(first):0"])
            XCTAssertTrue(probe.cancellations.isEmpty)
            XCTAssertEqual(probe.suspendedCount, 1)
            XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
            XCTAssertTrue(fixture.runtime.transitionOverlays.first === fixture.members[last])
            let terminal = expectTerminal(probe, ordinals: [0])

            probe.now += 1
            _ = fixture.runtime.tickAnimations(at: probe.now)
            await fulfillment(of: terminal, timeout: 5)
            XCTAssertEqual(
                probe.order, ["disappear:root-\(first):0", "disappear:root-\(last):0", "cancel:group:0"])
            XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
            XCTAssertEqual(probe.runs.count, 1)
            assertFinishedExactlyOnce(probe, ordinal: 0)
        }
    }

    func testTerminalCloseDrainsAGroupWhoseOtherOutgoingRootAlreadyDisappeared() async throws {
        let probe = MountedTaskOverlayProbe()
        let fixture = MountedTaskOverlayGroupFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let declaration = try fixture.installGroup(probe: probe)
        let ready = expectReady(probe)
        declaration.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        fixture.beginFade(durations: [1, 2])
        probe.now += 1.25
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertEqual(probe.order, ["disappear:root-0:0"])
        XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        let terminal = expectTerminal(probe, ordinals: [0])

        fixture.close()
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "cancel:group:0"])
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertEqual(probe.disappearances.count, 1)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        fixture.close()
        probe.now += 2
        _ = fixture.runtime.tickAnimations(at: probe.now)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        XCTAssertEqual(probe.suspendedCount, 0)
    }

    func testStaleSiblingCompletionCannotConsumeANewOverlayAdmissionForTheSamePhysicalNode() async throws {
        let probe = MountedTaskOverlayProbe()
        let fixture = MountedTaskOverlayGroupFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let original = try fixture.installGroup(probe: probe)
        let initialReady = expectReady(probe)
        original.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [initialReady], timeout: 5)
        let first = fixture.members[0]
        let reused = fixture.members[1]
        let firstDisappear = try XCTUnwrap(first.onDisappear)
        var didReenter = false
        var replacement: RetainedTaskDeclaration?
        first.onDisappear = { [weak fixture] in
            firstDisappear()
            guard !didReenter, let fixture else {
                XCTFail("An overlay already completing must not reenter disappearance")
                return
            }
            didReenter = true
            // Both roots were in the outer completed list. Complete the old
            // sibling during this callback, then admit a fresh departure for
            // that exact same ViewNode before the outer loop reaches it.
            _ = fixture.runtime.tickAnimations(at: probe.now)
            XCTAssertEqual(probe.order, ["disappear:root-0:0", "disappear:root-1:0"])
            XCTAssertTrue(probe.cancellations.isEmpty)
            XCTAssertFalse(reused.hasAppeared)
            XCTAssertFalse(fixture.runtime.transitionOverlays.contains { $0 === reused })
            reused.transition = .identity
            reused.opacity = 1
            fixture.runtime.root.addChild(reused)
            reused.onDisappear = { probe.recordDisappearance(label: "root-1", generation: 1) }
            do {
                let next = try fixture.installGroup(
                    probe: probe, targets: [reused], label: "replacement", generation: 1)
                replacement = next
                XCTAssertTrue(next.canCommit)
                next.deliver(restart: false)
                _ = fixture.runtime.renderScene()
                XCTAssertTrue(reused.hasAppeared)
                XCTAssertFalse(reused.hasPendingAppearanceCallbacks)
                reused.transition = RetainedTransition(kind: .opacity)
                withAnimation(.linear(duration: 2)) { fixture.runtime.root.removeChild(reused) }
                XCTAssertFalse(next.canCommit)
                XCTAssertTrue(fixture.runtime.transitionOverlays.contains { $0 === reused })
                XCTAssertEqual(reused.animationStates[.opacity]?.startTime, probe.now)
                XCTAssertEqual(reused.animationStates[.opacity]?.duration, 2)
            } catch {
                XCTFail("The replacement descriptor must complete native adoption: \(error)")
            }
        }
        fixture.beginFade(durations: [1, 1])
        let oldTerminal = expectTerminal(probe, ordinals: [0])
        let replacementReady = expectReady(probe)

        probe.now += 1.25
        _ = fixture.runtime.tickAnimations(at: probe.now)
        await fulfillment(of: oldTerminal + [replacementReady], timeout: 5)
        XCTAssertTrue(didReenter)
        XCTAssertNotNil(replacement)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "disappear:root-1:0", "cancel:group:0"])
        XCTAssertEqual(probe.runs.map(\.label), ["group", "replacement"])
        XCTAssertEqual(probe.cancellations.map { $0.run.ordinal }, [0])
        XCTAssertEqual(probe.completions, [0])
        XCTAssertEqual(probe.suspendedCount, 1)
        XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
        XCTAssertTrue(fixture.runtime.transitionOverlays.first === reused)

        probe.now += 1
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertEqual(reused.opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(probe.cancellations.count, 1)
        XCTAssertEqual(probe.disappearances.count, 2)
        let replacementTerminal = expectTerminal(probe, ordinals: [1])
        probe.now += 1.25
        _ = fixture.runtime.tickAnimations(at: probe.now)
        await fulfillment(of: replacementTerminal, timeout: 5)
        XCTAssertEqual(
            probe.order,
            [
                "disappear:root-0:0", "disappear:root-1:0", "cancel:group:0",
                "disappear:root-1:1", "cancel:replacement:1",
            ])
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        assertFinishedExactlyOnce(probe, ordinal: 1)
    }

    func testSiblingRemovalFromDisappearanceKeepsOneOriginalOverlayAndItsTask() async throws {
        let probe = MountedTaskOverlayProbe()
        let fixture = MountedTaskOverlayGroupFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let first = fixture.members[0]
        let sibling = fixture.members[1]
        let declaration = try fixture.installGroup(probe: probe, targets: [sibling], label: "sibling")
        let ready = expectReady(probe)
        declaration.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertTrue(first.hasAppeared)
        XCTAssertTrue(sibling.hasAppeared)
        sibling.transition = RetainedTransition(kind: .opacity)
        sibling.implicitReconcileAnimation = AnimationTransaction(duration: 2, easing: .linear)
        let firstDisappear = try XCTUnwrap(first.onDisappear)
        var didReenter = false
        first.onDisappear = { [weak fixture] in
            firstDisappear()
            guard let fixture, !didReenter else {
                XCTFail("The first sibling must disappear exactly once")
                return
            }
            didReenter = true
            XCTAssertFalse(declaration.canCommit)
            MountedTaskOverlayScope.none.perform { fixture.runtime.root.removeChild(sibling) }
            XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
            XCTAssertTrue(fixture.runtime.transitionOverlays.first === sibling)
            XCTAssertEqual(sibling.animationStates[.opacity]?.startTime, probe.now)
            XCTAssertEqual(sibling.animationStates[.opacity]?.duration, 2)
            XCTAssertEqual(probe.order, ["disappear:root-0:0"])
            XCTAssertTrue(probe.cancellations.isEmpty)
        }

        // The outer snapshot originally includes both siblings. Its later
        // visit must not detach or seed the already admitted sibling again.
        MountedTaskOverlayScope.none.perform { fixture.runtime.root.removeAllChildren() }
        XCTAssertTrue(didReenter)
        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
        XCTAssertTrue(fixture.runtime.transitionOverlays.first === sibling)
        XCTAssertEqual(sibling.animationStates[.opacity]?.startTime, probe.now)
        XCTAssertEqual(sibling.animationStates[.opacity]?.duration, 2)
        XCTAssertEqual(probe.order, ["disappear:root-0:0"])
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)

        probe.now += 1
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertEqual(sibling.opacity, 0.5, accuracy: 0.0001)
        XCTAssertTrue(sibling.hasAppeared)
        XCTAssertEqual(probe.order, ["disappear:root-0:0"])
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        let terminal = expectTerminal(probe, ordinals: [0])

        probe.now += 1.25
        _ = fixture.runtime.tickAnimations(at: probe.now)
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "disappear:root-1:0", "cancel:sibling:0"])
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(probe.runs.count, 1)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        fixture.close()
        _ = fixture.runtime.tickAnimations(at: probe.now + 2)
        assertFinishedExactlyOnce(probe, ordinal: 0)
    }

    func testDescendantRemovedFromDisappearanceKeepsItsTaskUntilItsOwnOverlayCompletes() async throws {
        let probe = MountedTaskOverlayProbe()
        let fixture = MountedTaskOverlayGroupFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let wrapper = fixture.members[0]
        let descendant = fixture.members[1]
        withTransaction(Transaction(animation: nil)) {
            wrapper.frame = Rect(x: 0, y: 0, width: 100, height: 60)
            descendant.frame = Rect(x: 0, y: 0, width: 80, height: 20)
            wrapper.addChild(descendant)
        }
        let declaration = try fixture.installGroup(probe: probe, targets: [descendant], label: "descendant")
        let ready = expectReady(probe)
        declaration.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertTrue(wrapper.hasAppeared)
        XCTAssertTrue(descendant.hasAppeared)
        descendant.transition = RetainedTransition(kind: .opacity)
        let wrapperDisappear = try XCTUnwrap(wrapper.onDisappear)
        var didReenter = false
        wrapper.onDisappear = { [weak wrapper, weak fixture] in
            wrapperDisappear()
            guard let wrapper, let fixture, !didReenter else {
                XCTFail("The wrapper must disappear exactly once")
                return
            }
            didReenter = true
            XCTAssertFalse(declaration.canCommit)
            withAnimation(.linear(duration: 2)) { wrapper.removeChild(descendant) }
            XCTAssertTrue(wrapper.children.isEmpty)
            XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
            XCTAssertTrue(fixture.runtime.transitionOverlays.first === descendant)
            XCTAssertEqual(descendant.animationStates[.opacity]?.startTime, probe.now)
            XCTAssertEqual(descendant.animationStates[.opacity]?.duration, 2)
            XCTAssertTrue(probe.cancellations.isEmpty)
        }

        // B leaves A's child table inside A's callback. No later traversal or
        // runtime detach of A can touch B's valid outgoing attachment.
        MountedTaskOverlayScope.none.perform { fixture.runtime.root.removeChild(wrapper) }
        XCTAssertTrue(didReenter)
        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertEqual(probe.order, ["disappear:root-0:0"])
        XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
        XCTAssertTrue(fixture.runtime.transitionOverlays.first === descendant)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)

        probe.now += 1
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertEqual(descendant.opacity, 0.5, accuracy: 0.0001)
        XCTAssertTrue(descendant.hasAppeared)
        XCTAssertEqual(probe.order, ["disappear:root-0:0"])
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        let terminal = expectTerminal(probe, ordinals: [0])

        probe.now += 1.25
        _ = fixture.runtime.tickAnimations(at: probe.now)
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "disappear:root-1:0", "cancel:descendant:0"])
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(probe.runs.count, 1)
        assertFinishedExactlyOnce(probe, ordinal: 0)
    }

    func testDescendantOverlayDoesNotDelayAnUnrelatedImmediateGroupInTheSameWrapper() async throws {
        let probe = MountedTaskOverlayProbe()
        let fixture = MountedTaskOverlayGroupFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let wrapper = fixture.members[0]
        let animated = fixture.members[1]
        let immediate = ViewNode(frame: Rect(x: 0, y: 25, width: 80, height: 20))
        immediate.onDisappear = { probe.recordDisappearance(label: "immediate", generation: 0) }
        withTransaction(Transaction(animation: nil)) {
            wrapper.frame = Rect(x: 0, y: 0, width: 100, height: 70)
            animated.frame = Rect(x: 0, y: 0, width: 80, height: 20)
            wrapper.addChild(animated)
            wrapper.addChild(immediate)
        }
        let animatedDeclaration = try fixture.installGroup(probe: probe, targets: [animated], label: "animated")
        let immediateDeclaration = try fixture.installGroup(probe: probe, targets: [immediate], label: "immediate")
        let ready = expectReady(probe, count: 2)
        animatedDeclaration.deliver(restart: false)
        immediateDeclaration.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.label).sorted(), ["animated", "immediate"])
        let animatedRun = try XCTUnwrap(probe.runs.first { $0.label == "animated" })
        let immediateRun = try XCTUnwrap(probe.runs.first { $0.label == "immediate" })
        XCTAssertEqual(probe.suspendedCount, 2)
        XCTAssertTrue(animatedDeclaration.canCommit)
        XCTAssertTrue(immediateDeclaration.canCommit)
        animated.transition = RetainedTransition(kind: .opacity)
        let wrapperDisappear = try XCTUnwrap(wrapper.onDisappear)
        var didReenter = false
        wrapper.onDisappear = { [weak wrapper, weak fixture] in
            wrapperDisappear()
            guard let wrapper, let fixture, !didReenter else {
                XCTFail("The wrapper must disappear exactly once")
                return
            }
            didReenter = true
            XCTAssertFalse(animatedDeclaration.canCommit)
            XCTAssertFalse(immediateDeclaration.canCommit)
            withAnimation(.linear(duration: 2)) { wrapper.removeChild(animated) }
            XCTAssertEqual(wrapper.children.count, 1)
            XCTAssertTrue(wrapper.children.first === immediate)
            XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
            XCTAssertTrue(fixture.runtime.transitionOverlays.first === animated)
            XCTAssertEqual(animated.animationStates[.opacity]?.startTime, probe.now)
            XCTAssertEqual(animated.animationStates[.opacity]?.duration, 2)
            XCTAssertEqual(probe.order, ["disappear:root-0:0"])
            XCTAssertTrue(probe.cancellations.isEmpty)
        }
        let immediateTerminal = expectTerminal(probe, ordinals: [immediateRun.ordinal])

        MountedTaskOverlayScope.none.perform { fixture.runtime.root.removeChild(wrapper) }
        XCTAssertTrue(didReenter)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "disappear:immediate:0", "cancel:immediate:0"])
        await fulfillment(of: immediateTerminal, timeout: 5)
        assertFinishedExactlyOnce(probe, ordinal: immediateRun.ordinal)
        XCTAssertEqual(probe.cancellations.map { $0.run.ordinal }, [immediateRun.ordinal])
        XCTAssertEqual(probe.suspendedCount, 1)
        XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
        XCTAssertTrue(fixture.runtime.transitionOverlays.first === animated)

        probe.now += 1
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertEqual(animated.opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "disappear:immediate:0", "cancel:immediate:0"])
        XCTAssertEqual(probe.cancellations.map { $0.run.ordinal }, [immediateRun.ordinal])
        XCTAssertEqual(probe.suspendedCount, 1)
        let animatedTerminal = expectTerminal(probe, ordinals: [animatedRun.ordinal])

        probe.now += 1.25
        _ = fixture.runtime.tickAnimations(at: probe.now)
        await fulfillment(of: animatedTerminal, timeout: 5)
        XCTAssertEqual(
            probe.order,
            [
                "disappear:root-0:0", "disappear:immediate:0", "cancel:immediate:0",
                "disappear:root-1:0", "cancel:animated:0",
            ])
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(probe.runs.count, 2)
        assertFinishedExactlyOnce(probe, ordinal: immediateRun.ordinal)
        assertFinishedExactlyOnce(probe, ordinal: animatedRun.ordinal)
    }

    func testDescendantRemovedFromDismantleKeepsItsTaskPastTheAncestorsShorterOverlay() async throws {
        let probe = MountedTaskOverlayProbe()
        let fixture = MountedTaskOverlayGroupFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let wrapper = fixture.members[0]
        let descendant = fixture.members[1]
        withTransaction(Transaction(animation: nil)) {
            wrapper.frame = Rect(x: 0, y: 0, width: 100, height: 60)
            descendant.frame = Rect(x: 0, y: 0, width: 80, height: 20)
            wrapper.addChild(descendant)
        }
        let declaration = try fixture.installGroup(probe: probe, targets: [descendant], label: "descendant")
        let ready = expectReady(probe)
        declaration.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        wrapper.transition = RetainedTransition(kind: .opacity)
        descendant.transition = RetainedTransition(kind: .opacity)
        var didReenter = false
        wrapper.onDismantlePlatformView = { [weak wrapper, weak fixture] node in
            guard let wrapper, let fixture, !didReenter else {
                XCTFail("The wrapper must be dismantled exactly once")
                return
            }
            didReenter = true
            XCTAssertTrue(node === wrapper)
            XCTAssertFalse(declaration.canCommit)
            withAnimation(.linear(duration: 2)) { wrapper.removeChild(descendant) }
            XCTAssertTrue(wrapper.children.isEmpty)
            XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
            XCTAssertTrue(fixture.runtime.transitionOverlays.first === descendant)
            XCTAssertEqual(descendant.animationStates[.opacity]?.startTime, probe.now)
            XCTAssertEqual(descendant.animationStates[.opacity]?.duration, 2)
            XCTAssertTrue(probe.order.isEmpty)
            XCTAssertTrue(probe.cancellations.isEmpty)
        }

        withAnimation(.linear(duration: 1)) { fixture.runtime.root.removeChild(wrapper) }
        XCTAssertTrue(didReenter)
        XCTAssertEqual(wrapper.animationStates[.opacity]?.startTime, probe.now)
        XCTAssertEqual(wrapper.animationStates[.opacity]?.duration, 1)
        XCTAssertEqual(descendant.animationStates[.opacity]?.startTime, probe.now)
        XCTAssertEqual(descendant.animationStates[.opacity]?.duration, 2)
        XCTAssertEqual(fixture.runtime.transitionOverlays.count, 2)
        XCTAssertTrue(fixture.runtime.transitionOverlays.contains { $0 === wrapper })
        XCTAssertTrue(fixture.runtime.transitionOverlays.contains { $0 === descendant })
        XCTAssertTrue(probe.order.isEmpty)
        XCTAssertTrue(probe.cancellations.isEmpty)

        probe.now += 1.25
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertEqual(probe.order, ["disappear:root-0:0"])
        XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
        XCTAssertTrue(fixture.runtime.transitionOverlays.first === descendant)
        XCTAssertEqual(descendant.opacity, 0.375, accuracy: 0.0001)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        let terminal = expectTerminal(probe, ordinals: [0])

        probe.now += 1
        _ = fixture.runtime.tickAnimations(at: probe.now)
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "disappear:root-1:0", "cancel:descendant:0"])
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(probe.runs.count, 1)
        assertFinishedExactlyOnce(probe, ordinal: 0)
    }

    func testAcceptedAbsenceCleanupCannotCancelTheAttemptMovedIntoAReplacementOverlay() async throws {
        let probe = MountedTaskOverlayProbe()
        let fixture = MountedTaskOverlayGroupFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let mount = RetainedTaskMountToken()
        let previous = try fixture.pendingGroupOperation(probe: probe, mount: mount, label: "original")
        defer { previous.finish() }
        try previous.acceptAll()
        XCTAssertEqual(previous.accepted.count, 1)
        let originalGroup = try XCTUnwrap(previous.accepted.first)
        let original = previous.declaration
        original.deliver(restart: false)
        previous.finish()
        let ready = expectReady(probe)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.label), ["original"])
        XCTAssertEqual(probe.suspendedCount, 1)

        let next = try fixture.pendingGroupOperation(probe: probe, mount: mount, label: "replacement")
        defer { next.finish() }
        let replacement = next.declaration
        next.prepareMember(0)
        // Native lifecycle-field acceptance claims S0's absence immediately.
        // The remaining field and member have not yet authorized S1.
        try next.copyAppear(0)
        XCTAssertFalse(original.canCommit)
        XCTAssertFalse(replacement.canCommit)
        XCTAssertTrue(next.accepted.isEmpty)
        try next.copyDisappear(0)
        XCTAssertFalse(replacement.canCommit)
        try next.acceptMember(1)
        XCTAssertEqual(next.accepted.count, 1)
        XCTAssertTrue(replacement.canCommit)
        replacement.deliver(restart: false)
        XCTAssertEqual(probe.runs.map(\.label), ["original"])
        XCTAssertTrue(probe.cancellations.isEmpty)

        // Sealing exposes the real accepted absence without executing its
        // task cleanup. No synthetic absence or physical departure is used
        // to manufacture the older permitsTransfer cleanup obligation.
        let disposition = next.journal.seal(completedCheckedAdoption: true)
        XCTAssertEqual(disposition.absentOrdinary.count, 1)
        let absence = try XCTUnwrap(disposition.absentOrdinary.first)
        XCTAssertTrue(absence.previous === originalGroup.contribution.receipt)
        XCTAssertTrue(disposition.acceptedCleanup.contains { $0 === absence.cleanup })
        XCTAssertEqual(disposition.acceptedOrdinaryGroups.count, 1)
        XCTAssertTrue(disposition.partialOrdinaryGroups.isEmpty)
        XCTAssertTrue(replacement.canCommit)

        fixture.beginFade(durations: [1, 1])
        XCTAssertFalse(replacement.canCommit)
        XCTAssertEqual(fixture.runtime.transitionOverlays.count, 2)
        XCTAssertTrue(
            fixture.members.allSatisfy { member in
                fixture.runtime.transitionOverlays.contains { $0 === member }
            })
        XCTAssertTrue(probe.order.isEmpty)
        XCTAssertTrue(probe.cancellations.isEmpty)

        // S1 has now left the live owner slot. S0's older journal must not
        // retain a second executable reference to S1's transferred attempt.
        next.journal.finishAcceptedTaskCleanup()
        XCTAssertTrue(probe.order.isEmpty)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        probe.now += 0.5
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertTrue(fixture.members.allSatisfy { $0.hasAppeared })
        for member in fixture.members { XCTAssertEqual(member.opacity, 0.5, accuracy: 0.0001) }
        XCTAssertTrue(probe.disappearances.isEmpty)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        let terminal = expectTerminal(probe, ordinals: [0])

        probe.now += 1
        _ = fixture.runtime.tickAnimations(at: probe.now)
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "disappear:root-1:0", "cancel:original:0"])
        XCTAssertEqual(probe.runs.map(\.label), ["original"])
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        next.journal.finishAcceptedTaskCleanup()
        fixture.close()
        _ = fixture.runtime.tickAnimations(at: probe.now + 2)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        withExtendedLifetime((previous, next)) {}
    }

    func testTerminalCancellationBeforeALaterSiblingSetupPreservesItsPhysicalDisappearance() async throws {
        let probe = MountedTaskOverlayProbe()
        let fixture = MountedTaskOverlayGroupFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let first = fixture.members[0]
        let sibling = fixture.members[1]
        let declaration = try fixture.installGroup(probe: probe, targets: [sibling], label: "sibling")
        let ready = expectReady(probe)
        declaration.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertTrue(first.hasAppeared)
        XCTAssertTrue(sibling.hasAppeared)
        sibling.transition = RetainedTransition(kind: .opacity)
        sibling.implicitReconcileAnimation = AnimationTransaction(duration: 2, easing: .linear)
        let originalSiblingAttachment = sibling.captureLazyListAttachmentProof()
        let firstDisappear = try XCTUnwrap(first.onDisappear)
        var didReenter = false
        first.onDisappear = { [weak fixture] in
            firstDisappear()
            guard let fixture, !didReenter else {
                XCTFail("The first sibling must disappear exactly once")
                return
            }
            didReenter = true
            XCTAssertTrue(originalSiblingAttachment.isCurrent)
            XCTAssertTrue(sibling.parent === fixture.runtime.root)
            XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
            // Stop task delivery without recursively removing the child table
            // whose outer disappearance callback is still executing.
            fixture.runtime.stopRenderLifecycleCallbacks()
            fixture.runtime.cancelRenderLifecycleTasks()
            XCTAssertEqual(probe.cancellationHandlerCalls, [0])
            XCTAssertEqual(probe.cancellations.map { $0.run.ordinal }, [0])
            XCTAssertEqual(probe.order, ["disappear:root-0:0", "cancel:sibling:0"])
            XCTAssertTrue(originalSiblingAttachment.isCurrent)
            XCTAssertTrue(sibling.parent === fixture.runtime.root)
            XCTAssertTrue(fixture.runtime.root.children.contains { $0 === sibling })
            XCTAssertTrue(sibling.hasAppeared)
            XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        }
        let terminal = expectTerminal(probe, ordinals: [0])

        MountedTaskOverlayScope.none.perform { fixture.runtime.root.removeAllChildren() }
        XCTAssertTrue(didReenter)
        XCTAssertFalse(declaration.canCommit)
        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertEqual(fixture.runtime.transitionOverlays.count, 1)
        XCTAssertTrue(fixture.runtime.transitionOverlays.first === sibling)
        XCTAssertEqual(sibling.animationStates[.opacity]?.startTime, probe.now)
        XCTAssertEqual(sibling.animationStates[.opacity]?.duration, 2)
        XCTAssertTrue(sibling.hasAppeared)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "cancel:sibling:0"])
        await fulfillment(of: terminal, timeout: 5)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        XCTAssertEqual(probe.suspendedCount, 0)

        probe.now += 1
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertEqual(sibling.opacity, 0.5, accuracy: 0.0001)
        XCTAssertTrue(sibling.hasAppeared)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "cancel:sibling:0"])
        assertFinishedExactlyOnce(probe, ordinal: 0)

        probe.now += 1.25
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "cancel:sibling:0", "disappear:root-1:0"])
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertFalse(sibling.hasAppeared)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        fixture.runtime.cancelRenderLifecycleTasks()
        _ = fixture.runtime.tickAnimations(at: probe.now + 2)
        XCTAssertEqual(probe.disappearances.count, 2)
        assertFinishedExactlyOnce(probe, ordinal: 0)
    }

    private func assertRawRemoval(_ operation: MountedTaskOverlayRawRemoval) async throws {
        let probe = MountedTaskOverlayProbe()
        let host = singleHost(probe)
        defer { finish(host, probe: probe) }
        let original = try taskNode("overlay", in: host.runtime)
        let parent = try XCTUnwrap(original.parent)
        let index = try XCTUnwrap(parent.children.firstIndex { $0 === original })
        await renderAndAcknowledge(host, probe: probe)
        withAnimation(.linear(duration: 1)) {
            switch operation {
            case .removeChild: parent.removeChild(at: index)
            case .replaceChild:
                parent.replaceChild(at: index, with: ViewNode(frame: original.frame))
            case .removeAllChildren: parent.removeAllChildren()
            }
        }
        XCTAssertFalse(parent.children.contains { $0 === original })
        XCTAssertTrue(host.runtime.transitionOverlays.contains { $0 === original })
        XCTAssertTrue(probe.order.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        advance(host, probe: probe, by: 0.5)
        XCTAssertEqual(original.opacity, 0.5, accuracy: 0.0001)
        XCTAssertTrue(probe.cancellations.isEmpty)
        let terminal = expectTerminal(probe, ordinals: [0])

        advance(host, probe: probe, by: 1)
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertEqual(probe.order, ["disappear:overlay:0", "cancel:overlay:0"])
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
        assertFinishedExactlyOnce(probe, ordinal: 0)
    }

    private func singleHost(_ probe: MountedTaskOverlayProbe) -> MountedOnChangeTestHost {
        let host = withTransaction(Transaction(animation: nil)) {
            MountedOnChangeTestHost {
                AnyView(
                    VStack {
                        if probe.isVisible {
                            mountedTaskOverlayLeaf(label: "overlay", generation: probe.generation, probe: probe)
                                .transition(.opacity)
                        }
                    })
            }
        }
        configure(host, probe: probe)
        return host
    }

    private func configure(_ host: MountedOnChangeTestHost, probe: MountedTaskOverlayProbe) {
        probe.runtime = host.runtime
        host.runtime.clock = { probe.now }
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    private func beginFade(_ host: MountedOnChangeTestHost, probe: MountedTaskOverlayProbe) {
        withAnimation(.linear(duration: 1)) {
            probe.isVisible = false
            host.reload()
        }
    }

    private func advance(_ host: MountedOnChangeTestHost, probe: MountedTaskOverlayProbe, by interval: Double) {
        probe.now += interval
        _ = host.runtime.tickAnimations(at: probe.now)
        host.render()
    }

    private func renderAndAcknowledge(
        _ host: MountedOnChangeTestHost, probe: MountedTaskOverlayProbe, count: Int = 1
    ) async {
        let ready = expectReady(probe, count: count)
        host.render()
        await fulfillment(of: [ready], timeout: 5)
    }

    private func expectReady(_ probe: MountedTaskOverlayProbe, count: Int = 1) -> XCTestExpectation {
        let ready = expectation(description: "Task installed its cancellation handler and owned continuation")
        ready.expectedFulfillmentCount = count
        ready.assertForOverFulfill = true
        probe.onReady = { _ in ready.fulfill() }
        return ready
    }

    private func expectTerminal(_ probe: MountedTaskOverlayProbe, ordinals: [Int]) -> [XCTestExpectation] {
        let cancelled = expectation(description: "Original task cancellation handler ran")
        let completed = expectation(description: "Original task action reached its terminal receipt")
        for receipt in [cancelled, completed] {
            receipt.expectedFulfillmentCount = ordinals.count
            receipt.assertForOverFulfill = true
        }
        probe.onCancelled = { run in
            XCTAssertTrue(ordinals.contains(run.ordinal))
            cancelled.fulfill()
        }
        probe.onCompleted = { run in
            XCTAssertTrue(ordinals.contains(run.ordinal))
            completed.fulfill()
        }
        return [cancelled, completed]
    }

    private func assertFinishedExactlyOnce(
        _ probe: MountedTaskOverlayProbe, ordinal: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(probe.cancellationHandlerCalls.filter { $0 == ordinal }.count, 1, file: file, line: line)
        XCTAssertEqual(probe.cancellations.filter { $0.run.ordinal == ordinal }.count, 1, file: file, line: line)
        XCTAssertEqual(probe.completions.filter { $0 == ordinal }.count, 1, file: file, line: line)
    }

    private func finish(_ host: MountedOnChangeTestHost, probe: MountedTaskOverlayProbe) {
        probe.clearAcknowledgements()
        host.runtime.clock = { probe.now }
        host.close()
        probe.releaseAll()
    }

    private func taskNode(_ identifier: String, in runtime: RetainedViewRuntime) throws -> ViewNode {
        let matches = nodes(in: runtime.root).filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }

    private func nodes(in root: ViewNode) -> [ViewNode] {
        var pending = [root]
        var result: [ViewNode] = []
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }

    private func detailedTransaction(animation: Animation?) -> Transaction {
        var transaction = Transaction(animation: animation)
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .bottom
        transaction.tracksVelocity = true
        return transaction
    }

    private func assertScope(
        _ snapshot: MountedTaskOverlaySnapshot, matches scope: MountedTaskOverlayScope,
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

private enum MountedTaskOverlayRawRemoval {
    case removeChild
    case replaceChild
    case removeAllChildren
}

@MainActor
private enum MountedTaskOverlayScope {
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

private struct MountedTaskOverlaySnapshot {
    let transaction: Transaction?
    let animationDuration: Double?
    let animationEasing: AnimationEasing?
    let isBuilding: Bool
}

private struct MountedTaskOverlayRun: Equatable, Sendable {
    let ordinal: Int
    let label: String
    let generation: Int
}

private struct MountedTaskOverlayCancellation {
    let run: MountedTaskOverlayRun
    let snapshot: MountedTaskOverlaySnapshot
}

@MainActor
private final class MountedTaskOverlayProbe {
    var isVisible = true
    var generation = 0
    var now = 100.0
    weak var runtime: RetainedViewRuntime?
    private(set) var runs: [MountedTaskOverlayRun] = []
    private(set) var cancellationHandlerCalls: [Int] = []
    private(set) var cancellations: [MountedTaskOverlayCancellation] = []
    private(set) var completions: [Int] = []
    private(set) var disappearances: [MountedTaskOverlaySnapshot] = []
    private(set) var order: [String] = []
    var onReady: ((MountedTaskOverlayRun) -> Void)?
    var onCancelled: ((MountedTaskOverlayRun) -> Void)?
    var onCompleted: ((MountedTaskOverlayRun) -> Void)?
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isReleased = false

    var suspendedCount: Int { continuations.count }

    func snapshot() -> MountedTaskOverlaySnapshot {
        MountedTaskOverlaySnapshot(
            transaction: currentTransaction,
            animationDuration: currentAnimationTransaction?.duration,
            animationEasing: currentAnimationTransaction?.easing,
            isBuilding: runtime?.hasActiveRetainedBuild == true)
    }

    func recordDisappearance(label: String, generation: Int) {
        disappearances.append(snapshot())
        order.append("disappear:\(label):\(generation)")
    }

    func run(label: String, generation: Int) async {
        let run = MountedTaskOverlayRun(ordinal: runs.count, label: label, generation: generation)
        runs.append(run)
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
                // The acknowledgment is inside the installed cancellation
                // handler and follows publication of its owned continuation.
                onReady?(run)
            }
        } onCancel: { [weak self] in
            // Every tested cancellation is synchronous MainActor removal,
            // physical disappearance, Canvas discard, or terminal cleanup.
            let probe = self
            MainActor.assumeIsolated {
                probe?.cancellationHandlerCalls.append(run.ordinal)
                probe?.cancel(run)
            }
        }
        completions.append(run.ordinal)
        onCompleted?(run)
    }

    private func cancel(_ run: MountedTaskOverlayRun) {
        guard !cancellations.contains(where: { $0.run.ordinal == run.ordinal }) else { return }
        cancellations.append(MountedTaskOverlayCancellation(run: run, snapshot: snapshot()))
        order.append("cancel:\(run.label):\(run.generation)")
        let continuation = continuations.removeValue(forKey: run.ordinal)
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
private func mountedTaskOverlayLeaf(label: String, generation: Int, probe: MountedTaskOverlayProbe) -> some View {
    // Reinsertion uses this exact callsite and ID; only the mounted lifetime
    // and captured generation change while its previous node fades out.
    Color.blue.frame(width: 40, height: 24)
        .accessibilityIdentifier(label)
        .task(id: 1) { await probe.run(label: label, generation: generation) }
        .onDisappear { probe.recordDisappearance(label: label, generation: generation) }
}

@MainActor
private final class MountedTaskOverlayEpoch: RetainedBuildEpoch {
    var canAdopt = true
    var canComplete = true
    func supersede() { canAdopt = false }
    func willAdopt() -> Bool { canAdopt }
    func commit() {}
    func abandon() { canAdopt = false }
    func finishAfterCallbacks() {}
}

@MainActor
private final class MountedTaskOverlayAdapterLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { MountedTaskOverlayAdapterEpoch() }
}

@MainActor
private final class MountedTaskOverlayAdapterEpoch: RetainedBuildEpoch {
    private var prepared = false
    var canAdopt: Bool { !prepared }
    func supersede() {}
    func willAdopt() -> Bool {
        guard !prepared else { return false }
        prepared = true
        return true
    }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}

/// Native descriptor transport is needed to put one Task owner on two roots.
/// Both lifecycle fields and every actual attachment are accepted through the
/// production journal; no callback bypasses group admission or render readiness.
@MainActor
private final class MountedTaskOverlayGroupFixture {
    let runtime: RetainedViewRuntime
    let members: [ViewNode]
    private let epoch = MountedTaskOverlayEpoch()

    init(probe: MountedTaskOverlayProbe) {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 100))
        runtime = RetainedViewRuntime(root: root)
        members = (0..<2).map { index in
            ViewNode(frame: Rect(x: 0, y: Double(index) * 25, width: 100, height: 20))
        }
        for (index, member) in members.enumerated() {
            root.addChild(member)
            member.onDisappear = { probe.recordDisappearance(label: "root-\(index)", generation: 0) }
        }
        runtime.clock = { probe.now }
        probe.runtime = runtime
    }

    func installGroup(
        probe: MountedTaskOverlayProbe, targets selected: [ViewNode]? = nil,
        label: String = "group", generation: Int = 0
    ) throws -> RetainedTaskDeclaration {
        let targets = selected ?? members
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        let transaction = RetainedBuildTransaction()
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: transaction)
        let context = RetainedTaskAdoptionContext(runtime: runtime, epoch: epoch, transaction: transaction)
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let group = try XCTUnwrap(attribution.registerGroup(kind: .scopedTask))
        let sources = targets.map { _ in ViewNode() }
        let declaration = RetainedTaskDeclaration(
            mount: RetainedTaskMountToken(), priority: .userInitiated,
            action: { await probe.run(label: label, generation: generation) },
            isMember: { true }, isCurrentProposal: { true })
        XCTAssertTrue(
            declaration.stage(groupSources: sources, in: runtime, descriptorAttribution: attribution, group: group))
        for source in sources {
            source.onAppearWithNode = { [weak declaration] node in declaration?.appear(on: node) }
            source.onDisappearWithNode = { [weak declaration] node in declaration?.disappear(from: node) }
        }
        _ = try XCTUnwrap(attribution.closeGroup(group))
        let preparation = try XCTUnwrap(journal.preparation())
        XCTAssertTrue(
            journal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(preparation: preparation, logicalMembershipPlans: [])
            ))
        XCTAssertTrue(journal.markMutationStarted())
        for (source, target) in zip(sources, targets) {
            let identifiers =
                source.existingRetainedTaskState?.descriptorCandidateDeclarations().flatMap { $0.declarations } ?? []
            journal.recordAcceptedDescriptorTaskDeclarationTransport(
                from: source, to: target, declarationIDs: identifiers)
            _ = journal.recordAcceptedAttachment(from: source, to: target)
            try copy(\ViewNode.onAppearWithNode, from: source, to: target, journal: journal)
            try copy(\ViewNode.onDisappearWithNode, from: source, to: target, journal: journal)
        }
        let accepted = journal.takeAcceptedDescriptorTaskGroups()
        XCTAssertEqual(accepted.count, 1)
        let acceptedGroup = try XCTUnwrap(accepted.first)
        XCTAssertEqual(acceptedGroup.members.count, targets.count)
        // The production journal holds weak source references; keep these
        // temporary candidates alive until association consumes their payloads.
        withExtendedLifetime(sources) {
            XCTAssertTrue(context.associateDescriptorAccepted(acceptedGroup, journal: journal))
        }
        _ = journal.seal(completedCheckedAdoption: true)
        journal.finishAcceptedTaskCleanup()
        journal.releaseUnadoptedTransport()
        scope.finish()
        return declaration
    }

    func pendingGroupOperation(
        probe: MountedTaskOverlayProbe, mount: RetainedTaskMountToken, label: String
    ) throws -> MountedTaskOverlayPendingGroupOperation {
        try MountedTaskOverlayPendingGroupOperation(
            runtime: runtime, epoch: epoch, targets: members, probe: probe, mount: mount, label: label)
    }

    private func copy<Value>(
        _ keyPath: ReferenceWritableKeyPath<ViewNode, Value>, from source: ViewNode, to target: ViewNode,
        journal: RetainedLazyListAdoptionJournal
    ) throws {
        XCTAssertTrue(journal.preparePropertyCopy(from: source, to: target, keyPath: keyPath))
        let previous = target[keyPath: keyPath]
        target[keyPath: keyPath] = source[keyPath: keyPath]
        _ = journal.recordAcceptedProperty(from: source, to: target, keyPath: keyPath)
        withExtendedLifetime(previous) {}
    }

    func beginFade(durations: [Double]) {
        for (member, duration) in zip(members, durations) {
            // Assign after initial render, so only removal owns a tween.
            member.transition = RetainedTransition(kind: .opacity)
            member.implicitReconcileAnimation = AnimationTransaction(duration: duration, easing: .linear)
        }
        MountedTaskOverlayScope.none.perform { runtime.root.removeAllChildren() }
    }

    func close() {
        runtime.stopRenderLifecycleCallbacks()
        epoch.canAdopt = false
        epoch.canComplete = false
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }

    func finish(probe: MountedTaskOverlayProbe) {
        probe.clearAcknowledgements()
        close()
        probe.releaseAll()
    }
}

/// Splits native descriptor adoption from its cleanup so a later physical
/// departure can intervene while the accepted original absence is pending.
@MainActor
private final class MountedTaskOverlayPendingGroupOperation {
    let declaration: RetainedTaskDeclaration
    let journal: RetainedLazyListAdoptionJournal
    private let scope: RetainedLazyListDescriptorBuildScope
    private let attribution: RetainedDescriptorComponentAttribution
    private let context: RetainedTaskAdoptionContext
    private let sources: [ViewNode]
    private let targets: [ViewNode]
    private(set) var accepted: [RetainedDescriptorAcceptedTaskGroup] = []

    init(
        runtime: RetainedViewRuntime, epoch: MountedTaskOverlayEpoch, targets: [ViewNode],
        probe: MountedTaskOverlayProbe, mount: RetainedTaskMountToken, label: String
    ) throws {
        self.targets = targets
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        self.scope = scope
        let transaction = RetainedBuildTransaction()
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: transaction)
        self.journal = journal
        context = RetainedTaskAdoptionContext(runtime: runtime, epoch: epoch, transaction: transaction)
        sources = targets.map { _ in ViewNode() }
        let declaration = RetainedTaskDeclaration(
            mount: mount, priority: .userInitiated,
            action: { await probe.run(label: label, generation: 0) },
            isMember: { true }, isCurrentProposal: { true })
        self.declaration = declaration
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        self.attribution = attribution
        let group = try XCTUnwrap(attribution.registerGroup(kind: .scopedTask))
        XCTAssertTrue(
            declaration.stage(groupSources: sources, in: runtime, descriptorAttribution: attribution, group: group))
        for source in sources {
            source.onAppearWithNode = { [weak declaration] node in declaration?.appear(on: node) }
            source.onDisappearWithNode = { [weak declaration] node in declaration?.disappear(from: node) }
        }
        _ = try XCTUnwrap(attribution.closeGroup(group))
        let preparation = try XCTUnwrap(journal.preparation())
        XCTAssertTrue(
            journal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(preparation: preparation, logicalMembershipPlans: [])
            ))
        XCTAssertTrue(journal.markMutationStarted())
    }

    func prepareMember(_ index: Int) {
        let source = sources[index]
        let target = targets[index]
        let identifiers =
            source.existingRetainedTaskState?.descriptorCandidateDeclarations().flatMap { $0.declarations } ?? []
        journal.recordAcceptedDescriptorTaskDeclarationTransport(from: source, to: target, declarationIDs: identifiers)
        _ = journal.recordAcceptedAttachment(from: source, to: target)
        acceptGroups()
    }

    func copyAppear(_ index: Int) throws {
        try copy(\ViewNode.onAppearWithNode, from: sources[index], to: targets[index])
    }

    func copyDisappear(_ index: Int) throws {
        try copy(\ViewNode.onDisappearWithNode, from: sources[index], to: targets[index])
    }

    func acceptMember(_ index: Int) throws {
        prepareMember(index)
        try copyAppear(index)
        try copyDisappear(index)
    }

    func acceptAll() throws {
        for index in sources.indices { try acceptMember(index) }
    }

    private func copy<Value>(
        _ keyPath: ReferenceWritableKeyPath<ViewNode, Value>, from source: ViewNode, to target: ViewNode
    ) throws {
        XCTAssertTrue(journal.preparePropertyCopy(from: source, to: target, keyPath: keyPath))
        let previous = target[keyPath: keyPath]
        target[keyPath: keyPath] = source[keyPath: keyPath]
        _ = journal.recordAcceptedProperty(from: source, to: target, keyPath: keyPath)
        acceptGroups()
        withExtendedLifetime(previous) {}
    }

    private func acceptGroups() {
        for group in journal.takeAcceptedDescriptorTaskGroups() {
            XCTAssertEqual(group.members.count, targets.count)
            accepted.append(group)
            withExtendedLifetime(sources) {
                XCTAssertTrue(context.associateDescriptorAccepted(group, journal: journal))
            }
        }
    }

    func finish() {
        _ = journal.seal(completedCheckedAdoption: true)
        journal.finishAcceptedTaskCleanup()
        journal.releaseUnadoptedTransport()
        scope.finish()
    }
}
