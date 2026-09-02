import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Actual task launches owe terminal cancellation even after unrelated raw
/// child-table writes leave their original native owner unreachable.
@MainActor
final class RetainedTaskAttemptLedgerTests: XCTestCase {
    func testUndeliveredAndUnrenderedDeclarationsDoNotAcquireRunningDebt() async throws {
        for mode in AttemptLedgerTestMode.allCases {
            let probe = AttemptLedgerProbe()
            let fixture = AttemptLedgerFixture(probe: probe)
            defer { fixture.finish(probe: probe) }
            let declaration = try fixture.install(probe: probe, target: fixture.source, mode: mode)
            XCTAssertTrue(declaration.canCommit)
            XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 0)
            declaration.deliver(restart: false)
            XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 0)
            XCTAssertTrue(probe.runs.isEmpty)
            fixture.close()
            await Task.yield()
            XCTAssertFalse(declaration.canCommit)
            XCTAssertTrue(probe.runs.isEmpty)
            XCTAssertTrue(probe.cancellations.isEmpty)
            XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 0)
        }
    }

    func testTerminalCloseCancelsOrdinaryOrphanWithoutBorrowingOldRemoval() async throws {
        let probe = AttemptLedgerProbe()
        let fixture = AttemptLedgerFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let ready = expectReady(probe, count: 1)
        let orphans = fixture.orphanTasks(probe: probe, mode: .ordinary, count: 1)
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(orphans.count, 1)
        XCTAssertEqual(probe.runs.count, 1)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 1)
        let terminal = expectTerminal(probe, count: 1)
        fixture.close()
        XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 0)
        await fulfillment(of: terminal, timeout: 5)
        assertTerminal(probe, count: 1)
        XCTAssertTrue(orphans.allSatisfy { $0.parent == nil && $0.retainedLazyListRuntime == nil })
    }

    func testTerminalTakeCoversAllOrphanedGroupsBeforeReentrantCancellation() async throws {
        let probe = AttemptLedgerProbe()
        let fixture = AttemptLedgerFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let ready = expectReady(probe, count: 2)
        let orphans = fixture.orphanTasks(probe: probe, mode: .managed, count: 2)
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(probe.runs.count, 2)
        XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 2)
        let terminal = expectTerminal(probe, count: 2)
        let reportCancellation = probe.onCancelled
        var didReenter = false
        probe.onCancelled = { [weak fixture] ordinal in
            reportCancellation?(ordinal)
            guard let fixture else {
                XCTFail("The host remains owned through its synchronous terminal operation")
                return
            }
            XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 0)
            guard !didReenter else { return }
            didReenter = true
            fixture.close()
            XCTAssertEqual(probe.cancellations.count, 1)
            XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 0)
        }
        fixture.close()
        XCTAssertTrue(didReenter)
        await fulfillment(of: terminal, timeout: 5)
        assertTerminal(probe, count: 2)
        fixture.close()
        assertTerminal(probe, count: 2)
        XCTAssertTrue(orphans.allSatisfy { $0.parent == nil && $0.retainedLazyListRuntime == nil })
    }

    func testCompletedOldAttemptCannotRemoveSameMountReplacement() async throws {
        let probe = AttemptLedgerProbe()
        probe.resumesOnCancellation = false
        let fixture = AttemptLedgerFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let mount = RetainedTaskMountToken()
        let original = try fixture.install(
            probe: probe, target: fixture.source, mode: .ordinary, mount: mount, label: "original")
        let ready = expectReady(probe, count: 1)
        original.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 1)
        let replacementReady = expectReady(probe, count: 1)
        let replacement = try fixture.install(
            probe: probe, target: fixture.source, mode: .ordinary, mount: mount, label: "replacement")
        replacement.deliver(restart: true)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [replacementReady], timeout: 5)
        XCTAssertEqual(probe.runs, ["original", "replacement"])
        XCTAssertEqual(probe.cancellations, [0])
        XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 2)
        let oldCompleted = expectation(description: "The displaced action actually returned")
        oldCompleted.assertForOverFulfill = true
        probe.onCompleted = { ordinal in
            XCTAssertEqual(ordinal, 0)
            oldCompleted.fulfill()
        }
        probe.resume(0)
        await fulfillment(of: [oldCompleted], timeout: 5)
        await requireAttemptCount(1, in: fixture.runtime)
        XCTAssertEqual(probe.completions, [0])
        XCTAssertEqual(probe.suspendedCount, 1)
        probe.resumesOnCancellation = true
        let cancelled = expectation(description: "The replacement receives its own cancellation")
        let completed = expectation(description: "The replacement action returns")
        for receipt in [cancelled, completed] { receipt.assertForOverFulfill = true }
        probe.onCancelled = { ordinal in
            XCTAssertEqual(ordinal, 1)
            cancelled.fulfill()
        }
        probe.onCompleted = { ordinal in
            XCTAssertEqual(ordinal, 1)
            completed.fulfill()
        }
        fixture.close()
        await fulfillment(of: [cancelled, completed], timeout: 5)
        assertTerminal(probe, count: 2)
        XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 0)
    }

    func testAlreadyCancelledAttemptRemainsTrackedUntilActionSettles() async throws {
        let probe = AttemptLedgerProbe()
        probe.resumesOnCancellation = false
        let fixture = AttemptLedgerFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let declaration = try fixture.install(probe: probe, target: fixture.source, mode: .managed)
        let ready = expectReady(probe, count: 1)
        declaration.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        fixture.runtime.root.removeChild(fixture.source)
        XCTAssertEqual(probe.cancellations, [0])
        XCTAssertEqual(probe.cancellationHandlerCalls, [0])
        XCTAssertTrue(probe.completions.isEmpty)
        XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 1)
        fixture.close()
        XCTAssertEqual(probe.cancellations, [0])
        XCTAssertEqual(probe.cancellationHandlerCalls, [0])
        XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 0)
        let completed = expectation(description: "The cooperatively held action eventually returns")
        completed.assertForOverFulfill = true
        probe.onCompleted = { ordinal in
            XCTAssertEqual(ordinal, 0)
            completed.fulfill()
        }
        probe.resume(0)
        await fulfillment(of: [completed], timeout: 5)
        assertTerminal(probe, count: 1)
    }

    func testCancellationBeforeFirstExecutionStillEntersTheAdmittedAction() async throws {
        for mode in AttemptLedgerTestMode.allCases {
            let probe = AttemptLedgerProbe()
            let fixture = AttemptLedgerFixture(probe: probe)
            defer { fixture.finish(probe: probe) }
            let declaration = try fixture.install(probe: probe, target: fixture.source, mode: mode)
            let ready = expectReady(probe, count: 1)
            let terminal = expectTerminal(probe, count: 1)
            declaration.deliver(restart: false)
            _ = fixture.runtime.renderScene()
            XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 1)
            XCTAssertTrue(probe.runs.isEmpty)
            fixture.close()
            XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 0)
            await fulfillment(of: [ready] + terminal, timeout: 5)
            XCTAssertEqual(probe.startedCancelled, [true])
            assertTerminal(probe, count: 1)
        }
    }

    func testRunningAttemptDoesNotKeepItsRuntimeOrPhysicalNodeAlive() async throws {
        for mode in AttemptLedgerTestMode.allCases {
            let probe = AttemptLedgerProbe()
            defer { probe.releaseAll() }
            let graph = AttemptLedgerWeakGraph()
            let ready = expectReady(probe, count: 1)
            let declaration = try launchWithoutKeepingGraph(probe: probe, graph: graph, mode: mode)
            XCTAssertNil(graph.runtime)
            XCTAssertNil(graph.node)
            XCTAssertFalse(declaration.canCommit)
            await fulfillment(of: [ready], timeout: 5)
            XCTAssertEqual(probe.suspendedCount, 1)
            XCTAssertTrue(probe.cancellations.isEmpty)
            let completed = expectation(description: "The action can finish after its native graph expires")
            completed.assertForOverFulfill = true
            probe.onCompleted = { ordinal in
                XCTAssertEqual(ordinal, 0)
                completed.fulfill()
            }
            probe.resume(0)
            await fulfillment(of: [completed], timeout: 5)
            XCTAssertEqual(probe.completions, [0])
            XCTAssertTrue(probe.cancellations.isEmpty)
            withExtendedLifetime(declaration) {}
        }
    }

    func testClosingOneRuntimeDoesNotCancelAnotherRuntimeAttempt() async throws {
        let firstProbe = AttemptLedgerProbe()
        let secondProbe = AttemptLedgerProbe()
        let first = AttemptLedgerFixture(probe: firstProbe)
        let second = AttemptLedgerFixture(probe: secondProbe)
        defer {
            first.finish(probe: firstProbe)
            second.finish(probe: secondProbe)
        }
        let firstDeclaration = try first.install(probe: firstProbe, target: first.source, mode: .managed)
        let secondDeclaration = try second.install(probe: secondProbe, target: second.source, mode: .ordinary)
        let firstReady = expectReady(firstProbe, count: 1)
        let secondReady = expectReady(secondProbe, count: 1)
        firstDeclaration.deliver(restart: false)
        secondDeclaration.deliver(restart: false)
        _ = first.runtime.renderScene()
        _ = second.runtime.renderScene()
        await fulfillment(of: [firstReady, secondReady], timeout: 5)
        let firstTerminal = expectTerminal(firstProbe, count: 1)
        first.close()
        await fulfillment(of: firstTerminal, timeout: 5)
        assertTerminal(firstProbe, count: 1)
        XCTAssertTrue(secondProbe.cancellations.isEmpty)
        XCTAssertEqual(secondProbe.suspendedCount, 1)
        XCTAssertEqual(second.runtime.retainedTaskAttempts.count, 1)
        let secondTerminal = expectTerminal(secondProbe, count: 1)
        second.close()
        await fulfillment(of: secondTerminal, timeout: 5)
        assertTerminal(secondProbe, count: 1)
    }

    private func expectReady(_ probe: AttemptLedgerProbe, count: Int) -> XCTestExpectation {
        let receipt = expectation(description: "Every admitted action installed its owned continuation")
        receipt.expectedFulfillmentCount = count
        receipt.assertForOverFulfill = true
        probe.onReady = { _ in receipt.fulfill() }
        return receipt
    }

    private func expectTerminal(_ probe: AttemptLedgerProbe, count: Int) -> [XCTestExpectation] {
        let cancelled = expectation(description: "Every original cancellation handler ran")
        let completed = expectation(description: "Every original action returned")
        for receipt in [cancelled, completed] {
            receipt.expectedFulfillmentCount = count
            receipt.assertForOverFulfill = true
        }
        probe.onCancelled = { _ in cancelled.fulfill() }
        probe.onCompleted = { _ in completed.fulfill() }
        return [cancelled, completed]
    }

    private func assertTerminal(
        _ probe: AttemptLedgerProbe, count: Int, file: StaticString = #filePath, line: UInt = #line
    ) {
        let originals = Array(0..<count)
        XCTAssertEqual(probe.cancellationHandlerCalls.sorted(), originals, file: file, line: line)
        XCTAssertEqual(probe.cancellations.sorted(), originals, file: file, line: line)
        XCTAssertEqual(probe.completions.sorted(), originals, file: file, line: line)
        XCTAssertEqual(probe.suspendedCount, 0, file: file, line: line)
    }

    private func requireAttemptCount(_ expected: Int, in runtime: RetainedViewRuntime) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while runtime.retainedTaskAttempts.count != expected, ContinuousClock.now < deadline {
            await Task.yield()
        }
        XCTAssertEqual(runtime.retainedTaskAttempts.count, expected)
    }

    @inline(never)
    private func launchWithoutKeepingGraph(
        probe: AttemptLedgerProbe, graph: AttemptLedgerWeakGraph, mode: AttemptLedgerTestMode
    ) throws -> RetainedTaskDeclaration {
        let fixture = AttemptLedgerFixture(probe: probe)
        graph.runtime = fixture.runtime
        graph.node = fixture.source
        let declaration = try fixture.install(probe: probe, target: fixture.source, mode: mode)
        declaration.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        XCTAssertEqual(fixture.runtime.retainedTaskAttempts.count, 1)
        return declaration
    }
}

private enum AttemptLedgerTestMode: CaseIterable {
    case ordinary
    case managed
}

@MainActor
private final class AttemptLedgerWeakGraph {
    weak var runtime: RetainedViewRuntime?
    weak var node: ViewNode?
}

@MainActor
private final class AttemptLedgerEpoch: RetainedBuildEpoch {
    var canAdopt = true
    var canComplete = true
    func supersede() { canAdopt = false }
    func willAdopt() -> Bool { canAdopt }
    func commit() {}
    func abandon() { canAdopt = false }
    func finishAfterCallbacks() {}
}

@MainActor
private final class AttemptLedgerFixture {
    let runtime: RetainedViewRuntime
    let source: ViewNode
    let destination: ViewNode
    private let epoch = AttemptLedgerEpoch()

    init(probe: AttemptLedgerProbe) {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 100))
        runtime = RetainedViewRuntime(root: root)
        source = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60))
        destination = ViewNode(frame: Rect(x: 0, y: 65, width: 100, height: 30))
        root.addChild(source)
        root.addChild(destination)
        runtime.clock = { probe.now }
    }

    func install(
        probe: AttemptLedgerProbe, target: ViewNode, mode: AttemptLedgerTestMode,
        mount: RetainedTaskMountToken = RetainedTaskMountToken(), label: String = "task"
    ) throws -> RetainedTaskDeclaration {
        let source = ViewNode()
        let transaction = RetainedBuildTransaction()
        let context = RetainedTaskAdoptionContext(runtime: runtime, epoch: epoch, transaction: transaction)
        let declaration = RetainedTaskDeclaration(
            mount: mount, priority: .userInitiated, action: { await probe.run(label: label) },
            isMember: { true }, isCurrentProposal: { true })
        source.onAppearWithNode = { [weak declaration] node in declaration?.appear(on: node) }
        source.onDisappearWithNode = { [weak declaration] node in declaration?.disappear(from: node) }
        switch mode {
        case .ordinary:
            declaration.stage(on: source, in: runtime)
            context.associate(source: source, target: target)
            target.onAppearWithNode = source.onAppearWithNode
            target.onDisappearWithNode = source.onDisappearWithNode
        case .managed:
            let scope = RetainedLazyListDescriptorBuildScope(
                origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
                ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
            let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: transaction)
            let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
            let group = try XCTUnwrap(attribution.registerGroup(kind: .scopedTask))
            XCTAssertTrue(
                declaration.stage(
                    groupSources: [source], in: runtime, descriptorAttribution: attribution, group: group))
            _ = try XCTUnwrap(attribution.closeGroup(group))
            let preparation = try XCTUnwrap(journal.preparation())
            XCTAssertTrue(
                journal.beginAdoption(
                    preparation,
                    preparedActivity: RetainedLazyListPreparedActivity(
                        preparation: preparation, logicalMembershipPlans: [])))
            XCTAssertTrue(journal.markMutationStarted())
            let identifiers =
                source.existingRetainedTaskState?.descriptorCandidateDeclarations().flatMap { $0.declarations } ?? []
            journal.recordAcceptedDescriptorTaskDeclarationTransport(
                from: source, to: target, declarationIDs: identifiers)
            _ = journal.recordAcceptedAttachment(from: source, to: target)
            try copy(\ViewNode.onAppearWithNode, from: source, to: target, journal: journal)
            try copy(\ViewNode.onDisappearWithNode, from: source, to: target, journal: journal)
            let accepted = journal.takeAcceptedDescriptorTaskGroups()
            XCTAssertEqual(accepted.count, 1)
            let acceptedGroup = try XCTUnwrap(accepted.first)
            XCTAssertEqual(acceptedGroup.members.count, 1)
            withExtendedLifetime(source) {
                XCTAssertTrue(context.associateDescriptorAccepted(acceptedGroup, journal: journal))
            }
            _ = journal.seal(completedCheckedAdoption: true)
            journal.finishAcceptedTaskCleanup()
            journal.releaseUnadoptedTransport()
            scope.finish()
        }
        XCTAssertTrue(declaration.canCommit)
        return declaration
    }

    func orphanTasks(probe: AttemptLedgerProbe, mode: AttemptLedgerTestMode, count: Int) -> [ViewNode] {
        let first = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 10))
        let later = (0..<count).map { index in
            ViewNode(frame: Rect(x: 0, y: Double(index + 1) * 15, width: 40, height: 10))
        }
        source.addChild(first)
        for node in later { source.addChild(node) }
        _ = runtime.renderScene()
        XCTAssertTrue(first.hasAppeared)
        XCTAssertTrue(later.allSatisfy(\.hasAppeared))
        XCTAssertTrue(later.allSatisfy { $0.existingRetainedTaskState == nil })
        let original = later.map { $0.captureLazyListAttachmentProof() }
        for node in [first] + later { node.transition = RetainedTransition(kind: .opacity) }
        var didReenter = false
        runtime.clock = { [weak self] in
            guard let self, !didReenter else { return probe.now }
            didReenter = true
            XCTAssertTrue(original.allSatisfy(\.isCurrent))
            for (index, node) in later.enumerated() {
                node.transition = .identity
                withTransaction(Transaction(animation: nil)) {
                    self.destination.addChild(node)
                    self.source.addChild(node)
                    XCTAssertFalse(original[index].isCurrent)
                    do {
                        let declaration = try self.install(
                            probe: probe, target: node, mode: mode, label: "replacement-\(index)")
                        declaration.deliver(restart: false)
                        _ = self.runtime.renderScene()
                        XCTAssertTrue(node.hasAppeared)
                        XCTAssertFalse(node.hasPendingAppearanceCallbacks)
                    } catch {
                        XCTFail("The replacement must complete actual task adoption: \(error)")
                    }
                }
                node.transition = RetainedTransition(kind: .opacity)
            }
            return probe.now
        }
        withAnimation(.linear(duration: 1)) { source.removeAllChildren() }
        XCTAssertTrue(didReenter)
        XCTAssertTrue(probe.cancellations.isEmpty)
        probe.now += 1.25
        _ = runtime.tickAnimations(at: probe.now)
        XCTAssertTrue(runtime.transitionOverlays.isEmpty)
        XCTAssertTrue(source.children.isEmpty)
        XCTAssertTrue(destination.children.isEmpty)
        XCTAssertTrue(later.allSatisfy { $0.parent == nil && $0.retainedLazyListRuntime == nil })
        XCTAssertTrue(probe.cancellations.isEmpty)
        return later
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

    func close() {
        runtime.stopRenderLifecycleCallbacks()
        epoch.canAdopt = false
        epoch.canComplete = false
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }

    func finish(probe: AttemptLedgerProbe) {
        probe.clearCallbacks()
        runtime.clock = { probe.now }
        close()
        probe.releaseAll()
    }
}

@MainActor
private final class AttemptLedgerProbe {
    var now = 100.0
    var resumesOnCancellation = true
    private(set) var runs: [String] = []
    private(set) var startedCancelled: [Bool] = []
    private(set) var cancellationHandlerCalls: [Int] = []
    private(set) var cancellations: [Int] = []
    private(set) var completions: [Int] = []
    var onReady: ((Int) -> Void)?
    var onCancelled: ((Int) -> Void)?
    var onCompleted: ((Int) -> Void)?
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isReleased = false

    var suspendedCount: Int { continuations.count }

    func run(label: String) async {
        let ordinal = runs.count
        runs.append(label)
        startedCancelled.append(Task.isCancelled)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                continuations[ordinal] = continuation
                if isReleased || (Task.isCancelled && resumesOnCancellation) { resume(ordinal) }
                onReady?(ordinal)
            }
        } onCancel: { [weak self] in
            let probe = self
            MainActor.assumeIsolated {
                guard let probe else { return }
                probe.cancellationHandlerCalls.append(ordinal)
                if !probe.cancellations.contains(ordinal) {
                    probe.cancellations.append(ordinal)
                    probe.onCancelled?(ordinal)
                }
                if probe.resumesOnCancellation { probe.resume(ordinal) }
            }
        }
        completions.append(ordinal)
        onCompleted?(ordinal)
    }

    func resume(_ ordinal: Int) {
        continuations.removeValue(forKey: ordinal)?.resume()
    }

    func clearCallbacks() {
        onReady = nil
        onCancelled = nil
        onCompleted = nil
    }

    func releaseAll() {
        isReleased = true
        let originals = Array(continuations.keys)
        for ordinal in originals { resume(ordinal) }
    }
}
