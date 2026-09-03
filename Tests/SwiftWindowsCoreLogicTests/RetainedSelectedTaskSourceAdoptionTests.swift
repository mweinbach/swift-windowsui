import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Native Task source-adoption coverage. The descriptor scope and journal are
/// real; ComponentHost and Runtime perform every accepted property/child write.
/// These cases contain no Buttons, lazy rows, UIA admission, or owned namespace.
/// The separate outer-task facade regression covers the namespace-bearing case.
@MainActor
final class RetainedSelectedTaskSourceAdoptionTests: XCTestCase {
    func testFreshNestedBoundaryInsertionAcceptsOneSelectedTask() async throws {
        let probe = SelectedTaskSourceProbe()
        let fixture = SelectedTaskSourceFixture()
        defer { fixture.finish(probe: probe) }
        let operation = try SelectedTaskSourceOperation(
            fixture: fixture, selection: 1, taskID: 1, mount: RetainedTaskMountToken(),
            action: { await probe.run(id: 1) })
        XCTAssertTrue(operation.constructionPath.isCurrent)
        XCTAssertNil(operation.outer.parent)
        XCTAssertNil(operation.outer.retainedLazyListRuntime)
        let ready = expectReady(probe, number: 0, id: 1, fixture: fixture)

        let adoption = operation.adopt()
        assertNativeCompletion(adoption, operation: operation, fixture: fixture)
        let actual = try fixture.installedNodes()
        XCTAssertTrue(actual.outer === operation.outer)
        XCTAssertTrue(actual.inner === operation.inner)
        XCTAssertTrue(actual.selected === operation.selected)
        assertTaskFacts(adoption.disposition, operation: operation, actual: actual)
        XCTAssertTrue(operation.declaration.canCommit)
        operation.declaration.deliver(restart: false)
        fixture.render()

        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.id), [1])
        XCTAssertEqual(probe.suspendedCount, 1)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertTrue(probe.completions.isEmpty)
        let terminal = expectTerminal(probe, number: 0, id: 1)
        fixture.runtime.root.removeAllChildren()
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertNil(actual.outer.parent)
        XCTAssertNil(actual.selected.retainedLazyListRuntime)
        XCTAssertFalse(operation.declaration.canCommit)
        XCTAssertEqual(probe.cancellations, [0])
        XCTAssertEqual(probe.completions, [0])
        XCTAssertEqual(probe.suspendedCount, 0)
        XCTAssertTrue(fixture.runtime.permitsRetainedActionInvocation)
    }

    func testChangedTaskDecisionKeepsLiteralBoundaryChildrenAndSelectedAttachment() async throws {
        let probe = SelectedTaskSourceProbe()
        let fixture = SelectedTaskSourceFixture()
        defer { fixture.finish(probe: probe) }
        let mount = RetainedTaskMountToken()
        let original = try SelectedTaskSourceOperation(
            fixture: fixture, selection: 1, taskID: 1, mount: mount,
            action: { await probe.run(id: 1) })
        let firstReady = expectReady(probe, number: 0, id: 1, fixture: fixture)
        let firstAdoption = original.adopt()
        assertNativeCompletion(firstAdoption, operation: original, fixture: fixture)
        original.declaration.deliver(restart: false)
        fixture.render()
        await fulfillment(of: [firstReady], timeout: 5)
        let before = try fixture.installedNodes()
        let selectedAttachment = before.selected.captureLazyListAttachmentProof()
        var physicalDepartures = 0
        before.selected.onDismantlePlatformView = { _ in physicalDepartures += 1 }

        // The source leaves have the same native identities. Reconciliation
        // returns the original actual child objects at both boundary levels.
        // Task decision 1 -> 2 is explicit; same-ID continuation is not tested.
        let replacement = try SelectedTaskSourceOperation(
            fixture: fixture, selection: 1, taskID: 2, mount: mount,
            action: { await probe.run(id: 2) })
        replacement.selected.onDismantlePlatformView = { _ in physicalDepartures += 1 }
        let oldTerminal = expectTerminal(probe, number: 0, id: 1)
        let nextReady = expectReady(probe, number: 1, id: 2, fixture: fixture)
        let adoption = replacement.adopt()
        assertNativeCompletion(adoption, operation: replacement, fixture: fixture)
        let after = try fixture.installedNodes()
        XCTAssertTrue(after.outer === before.outer)
        XCTAssertTrue(after.inner === before.inner)
        XCTAssertTrue(after.selected === before.selected)
        XCTAssertTrue(after.outer.children.first === before.inner)
        XCTAssertTrue(after.inner.children.first === before.selected)
        XCTAssertTrue(selectedAttachment.isCurrent)
        XCTAssertEqual(physicalDepartures, 0)
        XCTAssertTrue(replacement.selected.parent === replacement.inner)
        XCTAssertNil(replacement.outer.retainedLazyListRuntime)
        assertTaskFacts(adoption.disposition, operation: replacement, actual: after)
        XCTAssertTrue(replacement.declaration.canCommit)
        replacement.declaration.deliver(restart: true)
        fixture.render()

        await fulfillment(of: oldTerminal + [nextReady], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.id), [1, 2])
        XCTAssertEqual(probe.cancellations, [0])
        XCTAssertEqual(probe.completions, [0])
        XCTAssertEqual(probe.suspendedCount, 1)
        XCTAssertEqual(physicalDepartures, 0)
        XCTAssertTrue(selectedAttachment.isCurrent)
        let lastTerminal = expectTerminal(probe, number: 1, id: 2)
        fixture.runtime.root.removeAllChildren()
        await fulfillment(of: lastTerminal, timeout: 5)
        XCTAssertEqual(probe.cancellations, [0, 1])
        XCTAssertEqual(probe.completions, [0, 1])
        XCTAssertEqual(probe.suspendedCount, 0)
    }

    func testSourceChildrenABABeforeTransferRefusesTaskWithoutChangingOrdinaryReplacement() async throws {
        try await assertSourceMutationRefusal(.beforeTransfer)
    }

    func testSourceChildrenABAAfterOwnRemovalCannotRefreshTheConsumedTaskTicket() async throws {
        try await assertSourceMutationRefusal(.afterSourceRemoval)
    }

    private func assertSourceMutationRefusal(_ phase: SelectedTaskSourceMutationPhase) async throws {
        let probe = SelectedTaskSourceProbe()
        let fixture = SelectedTaskSourceFixture()
        defer { fixture.finish(probe: probe) }
        let original = try SelectedTaskSourceOperation(
            fixture: fixture, selection: 1, taskID: 1, mount: RetainedTaskMountToken(),
            action: { await probe.run(id: 1) })
        let ready = expectReady(probe, number: 0, id: 1, fixture: fixture)
        let firstAdoption = original.adopt()
        assertNativeCompletion(firstAdoption, operation: original, fixture: fixture)
        original.declaration.deliver(restart: false)
        fixture.render()
        await fulfillment(of: [ready], timeout: 5)
        let old = try fixture.installedNodes()
        old.selected.onDisappear = {
            XCTAssertTrue(probe.cancellations.isEmpty)
            probe.events.append("old-disappear")
        }
        let terminal = expectTerminal(probe, number: 0, id: 1)
        var actionReleases = 0

        let observation = try performRefusedSourceMutation(
            phase, fixture: fixture, probe: probe, original: original.declaration,
            old: old, onActionRelease: { actionReleases += 1 })

        // No actor suspension has occurred since delivery/render. A created
        // Task would still own the candidate action while waiting to enter the
        // MainActor probe. Positive release proves that no attempt was created.
        XCTAssertEqual(actionReleases, 1)
        XCTAssertEqual(observation.callbackCount, 1)
        XCTAssertTrue(observation.nativeCompleted)
        XCTAssertTrue(observation.nativeDidMutate)
        XCTAssertTrue(observation.normalContributionIsActive)
        XCTAssertEqual(observation.acceptedTaskGroups, 0)
        let actual = try fixture.installedNodes()
        XCTAssertTrue(actual.outer === old.outer)
        XCTAssertTrue(actual.inner === old.inner)
        XCTAssertTrue(actual.selected === observation.selected)
        XCTAssertEqual(actual.selected.accessibilityIdentifier, "selected-source-2")
        XCTAssertTrue(actual.selected.hasAppeared)
        XCTAssertFalse(actual.selected.existingRetainedTaskState?.hasCommittedSlots ?? false)
        XCTAssertNil(old.selected.parent)
        XCTAssertNil(old.selected.retainedLazyListRuntime)
        XCTAssertFalse(original.declaration.canCommit)
        XCTAssertEqual(probe.runs.map(\.id), [1])
        XCTAssertEqual(probe.cancellations, [0])
        let disappeared = try XCTUnwrap(probe.events.firstIndex(of: "old-disappear"))
        let cancelled = try XCTUnwrap(probe.events.firstIndex(of: "cancel-0"))
        XCTAssertLessThan(disappeared, cancelled)

        await fulfillment(of: terminal, timeout: 5)
        XCTAssertEqual(probe.completions, [0])
        XCTAssertEqual(probe.suspendedCount, 0)
        XCTAssertEqual(actionReleases, 1)
        fixture.runtime.root.removeAllChildren()
        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertEqual(probe.cancellations, [0])
        XCTAssertEqual(probe.completions, [0])
        XCTAssertTrue(fixture.runtime.permitsRetainedActionInvocation)
    }

    @inline(never)
    private func performRefusedSourceMutation(
        _ phase: SelectedTaskSourceMutationPhase, fixture: SelectedTaskSourceFixture,
        probe: SelectedTaskSourceProbe, original: RetainedTaskDeclaration, old: SelectedTaskSourceNodes,
        onActionRelease: @escaping @MainActor () -> Void
    ) throws -> SelectedTaskSourceRefusalObservation {
        let actionLifetime = SelectedTaskSourceActionLifetime(onRelease: onActionRelease)
        let operation = try SelectedTaskSourceOperation(
            fixture: fixture, selection: 2, taskID: 2, mount: RetainedTaskMountToken(),
            action: {
                await probe.run(id: 2)
                withExtendedLifetime(actionLifetime) {}
            })
        let sourceAttachment = operation.selected.captureLazyListAttachmentProof()
        let originalPath = operation.constructionPath
        let sourceInner = operation.inner
        let sourceSelected = operation.selected
        var callbackCount = 0

        switch phase {
        case .beforeTransfer:
            old.selected.onDismantlePlatformView = { [weak sourceInner, weak sourceSelected] _ in
                guard callbackCount == 0, let sourceInner, let sourceSelected else { return }
                callbackCount += 1
                XCTAssertFalse(original.canCommit)
                XCTAssertTrue(probe.cancellations.isEmpty)
                XCTAssertTrue(originalPath.isCurrent)
                XCTAssertTrue(sourceAttachment.isCurrent)
                XCTAssertEqual(sourceInner.children.count, 1)
                XCTAssertTrue(sourceInner.children.first === sourceSelected)
                let decoy = ViewNode()
                sourceInner.addChild(decoy)
                XCTAssertEqual(sourceInner.children.count, 2)
                sourceInner.removeChild(decoy)
                XCTAssertEqual(sourceInner.children.count, 1)
                XCTAssertTrue(sourceInner.children.first === sourceSelected)
                XCTAssertTrue(sourceSelected.parent === sourceInner)
                XCTAssertTrue(sourceAttachment.isCurrent)
                XCTAssertFalse(originalPath.isCurrent)
            }
        case .afterSourceRemoval:
            sourceSelected.onDismantlePlatformView = { [weak sourceInner, weak sourceSelected] actual in
                guard callbackCount == 0, let sourceInner, let sourceSelected else { return }
                callbackCount += 1
                XCTAssertTrue(actual === sourceSelected)
                // Runtime's own source children removal has already happened,
                // but its source parent-nil write has not. Do not repair it.
                XCTAssertTrue(sourceInner.children.isEmpty)
                XCTAssertTrue(sourceSelected.parent === sourceInner)
                XCTAssertFalse(originalPath.isCurrent)
                let decoy = ViewNode()
                sourceInner.addChild(decoy)
                XCTAssertTrue(sourceInner.children.first === decoy)
                sourceInner.removeChild(decoy)
                XCTAssertTrue(sourceInner.children.isEmpty)
                XCTAssertTrue(sourceSelected.parent === sourceInner)
            }
        }

        let adoption = operation.adopt()
        assertNativeCompletion(adoption, operation: operation, fixture: fixture)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertFalse(operation.declaration.canCommit)
        XCTAssertFalse(operation.taskContribution.isActive)
        operation.declaration.deliver(restart: false)
        fixture.render()
        XCTAssertFalse(operation.selected.existingRetainedTaskState?.hasCommittedSlots ?? false)
        let taskGroups = adoption.disposition.acceptedOrdinaryGroups.filter {
            $0.proposal.group === operation.taskGroup
        }
        XCTAssertTrue(taskGroups.isEmpty)
        // Keep source nodes through all native publication. The returned
        // observation does not retain the proposed declaration or action.
        withExtendedLifetime((operation, originalPath, sourceAttachment)) {}
        return SelectedTaskSourceRefusalObservation(
            selected: operation.selected, callbackCount: callbackCount,
            nativeCompleted: adoption.native.completed, nativeDidMutate: adoption.native.didMutate,
            normalContributionIsActive: operation.normalContribution.isActive,
            acceptedTaskGroups: taskGroups.count)
    }

    private func assertNativeCompletion(
        _ adoption: SelectedTaskSourceAdoption, operation: SelectedTaskSourceOperation,
        fixture: SelectedTaskSourceFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(adoption.native.completed, file: file, line: line)
        XCTAssertTrue(adoption.native.didMutate, file: file, line: line)
        XCTAssertEqual(adoption.disposition.stop, .completedCheckedAdoption, file: file, line: line)
        XCTAssertTrue(operation.normalContribution.isActive, file: file, line: line)
        XCTAssertEqual(
            adoption.disposition.acceptedOrdinaryGroups.filter { $0.proposal.group === operation.normalGroup }.count,
            1, file: file, line: line)
        XCTAssertEqual(fixture.runtime.root.children.count, 1, file: file, line: line)
        XCTAssertTrue(fixture.runtime.permitsRetainedActionInvocation, file: file, line: line)
    }

    private func assertTaskFacts(
        _ disposition: RetainedLazyListAdoptionDisposition, operation: SelectedTaskSourceOperation,
        actual: SelectedTaskSourceNodes, file: StaticString = #filePath, line: UInt = #line
    ) {
        let accepted = disposition.acceptedOrdinaryGroups.filter { $0.proposal.group === operation.taskGroup }
        XCTAssertEqual(accepted.count, 1, file: file, line: line)
        guard let group = accepted.first else { return }
        XCTAssertTrue(group.receipt.isActive, file: file, line: line)
        XCTAssertEqual(Set(group.acceptedFacets.map { ObjectIdentifier($0.source) }).count, 1, file: file, line: line)
        var attachments: [ViewNode] = []
        var hooks = 0
        var declarations = 0
        for fact in group.acceptedFacets {
            XCTAssertTrue(fact.actual.isAttached, file: file, line: line)
            switch fact.nativeField {
            case .childAttachment:
                if let node = fact.actual.node { attachments.append(node) }
            case .nodeProperty(let keyPath):
                XCTAssertTrue(
                    keyPath == \ViewNode.onAppearWithNode || keyPath == \ViewNode.onDisappearWithNode,
                    file: file, line: line)
                XCTAssertTrue(fact.actual.node === actual.selected, file: file, line: line)
                hooks += 1
            case .scopedTaskDeclaration(let declaration):
                XCTAssertTrue(declaration === operation.declaration.declarationID, file: file, line: line)
                XCTAssertTrue(fact.actual.node === actual.selected, file: file, line: line)
                declarations += 1
            default:
                XCTFail("A routed Task received an unrelated native facet", file: file, line: line)
            }
        }
        XCTAssertEqual(attachments.count, 2, file: file, line: line)
        XCTAssertTrue(attachments.contains { $0 === actual.outer }, file: file, line: line)
        XCTAssertTrue(attachments.contains { $0 === actual.inner }, file: file, line: line)
        XCTAssertEqual(hooks, 2, file: file, line: line)
        XCTAssertEqual(declarations, 1, file: file, line: line)
    }

    private func expectReady(
        _ probe: SelectedTaskSourceProbe, number: Int, id: Int, fixture: SelectedTaskSourceFixture
    ) -> XCTestExpectation {
        let ready = expectation(description: "Task \(id) entered after installing its cancellation handler")
        ready.assertForOverFulfill = true
        probe.onReady = { run in
            defer { ready.fulfill() }
            XCTAssertEqual(run.number, number)
            XCTAssertEqual(run.id, id)
            XCTAssertFalse(run.wasCancelledAtEntry)
            do {
                let actual = try fixture.installedNodes()
                XCTAssertTrue(actual.selected.hasAppeared)
                XCTAssertTrue(actual.selected.parent === actual.inner)
                XCTAssertTrue(actual.inner.parent === actual.outer)
                XCTAssertNotNil(actual.selected.onAppearWithNode)
                XCTAssertNotNil(actual.selected.onDisappearWithNode)
                XCTAssertNil(actual.outer.onAppearWithNode)
                XCTAssertNil(actual.outer.onDisappearWithNode)
                XCTAssertNil(actual.inner.onAppearWithNode)
                XCTAssertNil(actual.inner.onDisappearWithNode)
                XCTAssertFalse(actual.outer.existingRetainedTaskState?.hasCommittedSlots ?? false)
                XCTAssertFalse(actual.inner.existingRetainedTaskState?.hasCommittedSlots ?? false)
                XCTAssertEqual(probe.suspendedCount, 1)
            } catch {
                XCTFail("Entered Task must belong to the installed selected node: \(error)")
            }
        }
        return ready
    }

    private func expectTerminal(
        _ probe: SelectedTaskSourceProbe, number: Int, id: Int
    ) -> [XCTestExpectation] {
        let cancelled = expectation(description: "Task \(id) cancellation was acknowledged")
        let completed = expectation(description: "Task \(id) completion was acknowledged")
        cancelled.assertForOverFulfill = true
        completed.assertForOverFulfill = true
        probe.onCancelled = { run in
            XCTAssertEqual(run.number, number)
            XCTAssertEqual(run.id, id)
            cancelled.fulfill()
        }
        probe.onCompleted = { run in
            XCTAssertEqual(run.number, number)
            XCTAssertEqual(run.id, id)
            completed.fulfill()
        }
        return [cancelled, completed]
    }
}

private enum SelectedTaskSourceMutationPhase {
    case beforeTransfer
    case afterSourceRemoval
}

@MainActor
private struct SelectedTaskSourceNodes {
    let outer: ViewNode
    let inner: ViewNode
    let selected: ViewNode
}

@MainActor
private struct SelectedTaskSourceAdoption {
    let native: RetainedLazyListAdoptionResult
    let disposition: RetainedLazyListAdoptionDisposition
}

@MainActor
private struct SelectedTaskSourceRefusalObservation {
    let selected: ViewNode
    let callbackCount: Int
    let nativeCompleted: Bool
    let nativeDidMutate: Bool
    let normalContributionIsActive: Bool
    let acceptedTaskGroups: Int
}

@MainActor
private final class SelectedTaskSourceEpoch: RetainedBuildEpoch {
    var canAdopt = true
    var canComplete = true
    func supersede() { canAdopt = false }
    func willAdopt() -> Bool { canAdopt }
    func commit() {}
    func abandon() { canAdopt = false }
    func finishAfterCallbacks() {}
}

@MainActor
private final class SelectedTaskSourceFixture {
    let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 180, height: 80)))
    let epoch = SelectedTaskSourceEpoch()
    private var isClosed = false

    func installedNodes() throws -> SelectedTaskSourceNodes {
        XCTAssertEqual(runtime.root.children.count, 1)
        let outer = try XCTUnwrap(runtime.root.children.first)
        XCTAssertEqual(outer.selectedContentRole, .viewThatFits)
        XCTAssertEqual(outer.children.count, 1)
        let inner = try XCTUnwrap(outer.children.first)
        XCTAssertEqual(inner.selectedContentRole, .viewThatFits)
        XCTAssertEqual(inner.children.count, 1)
        let selected = try XCTUnwrap(inner.children.first)
        XCTAssertNil(selected.selectedContentRole)
        return SelectedTaskSourceNodes(outer: outer, inner: inner, selected: selected)
    }

    func render() { _ = runtime.renderScene() }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        runtime.stopRenderLifecycleCallbacks()
        epoch.canAdopt = false
        epoch.canComplete = false
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }

    func finish(probe: SelectedTaskSourceProbe) {
        probe.clearAcknowledgements()
        close()
        probe.releaseAll()
    }
}

@MainActor
private final class SelectedTaskSourceOperation {
    let outer: ViewNode
    let inner: ViewNode
    let selected: ViewNode
    let constructionPath: RetainedSelectedContentPath
    let declaration: RetainedTaskDeclaration
    let taskGroup: RetainedDescriptorGroupID
    let taskContribution: RetainedDescriptorContributionReceipt
    let normalGroup: RetainedDescriptorGroupID
    let normalContribution: RetainedDescriptorContributionReceipt
    private let fixture: SelectedTaskSourceFixture
    private let scope: RetainedLazyListDescriptorBuildScope
    private let journal: RetainedLazyListAdoptionJournal
    private let context: RetainedTaskAdoptionContext

    init(
        fixture: SelectedTaskSourceFixture, selection: Int, taskID: Int, mount: RetainedTaskMountToken,
        action: @escaping @Sendable () async -> Void
    ) throws {
        self.fixture = fixture
        let selected = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 24))
        selected.retainedViewIdentity = RetainedViewIdentity().appending(.slot(selection))
        selected.accessibilityIdentifier = "selected-source-\(selection)"
        let inner = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)
        inner.retainedViewIdentity = RetainedViewIdentity().appending(.slot(20))
        inner.frame = Rect(x: 0, y: 0, width: 100, height: 24)
        let outer = ViewNode.selectedContentBoundary(role: .viewThatFits, child: inner)
        outer.retainedViewIdentity = RetainedViewIdentity().appending(.slot(10))
        outer.frame = Rect(x: 0, y: 0, width: 100, height: 24)
        self.outer = outer
        self.inner = inner
        self.selected = selected
        let constructionPath = try XCTUnwrap(outer.captureSelectedContentConstructionPath())
        self.constructionPath = constructionPath
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: fixture.runtime.lazyListLogicalHostLifetime,
            ownerLifetime: fixture.runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        self.scope = scope
        let transaction = RetainedBuildTransaction()
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: transaction)
        self.journal = journal
        context = RetainedTaskAdoptionContext(runtime: fixture.runtime, epoch: fixture.epoch, transaction: transaction)
        journal.seedExistingContributions(from: fixture.runtime.root.children)
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let taskGroup = try XCTUnwrap(attribution.registerGroup(kind: .scopedTask))
        self.taskGroup = taskGroup
        let declaration = RetainedTaskDeclaration(
            mount: mount, priority: .userInitiated, action: action,
            isMember: { true }, isCurrentProposal: { true })
        self.declaration = declaration
        XCTAssertTrue(
            declaration.stage(
                groupSources: [outer], in: fixture.runtime, descriptorAttribution: attribution, group: taskGroup,
                selectedContentPaths: [constructionPath], candidateConstruction: nil),
            "Task \(taskID) must stage the original physical output and selected construction path")
        selected.onAppearWithNode = { [weak declaration] actual in declaration?.appear(on: actual) }
        selected.onDisappearWithNode = { [weak declaration] actual in declaration?.disappear(from: actual) }
        // Mirror the later generic source registration performed by Core. This
        // nil-route call must preserve the task's original selected source.
        XCTAssertTrue(attribution.recordSourceOutput(outer, group: taskGroup))
        taskContribution = try XCTUnwrap(attribution.contribution(for: taskGroup))
        _ = try XCTUnwrap(attribution.closeGroup(taskGroup))
        let normalGroup = try XCTUnwrap(attribution.registerGroup(kind: .structure))
        self.normalGroup = normalGroup
        XCTAssertTrue(attribution.recordSourceOutput(outer, group: normalGroup))
        normalContribution = try XCTUnwrap(attribution.contribution(for: normalGroup))
        _ = try XCTUnwrap(attribution.closeGroup(normalGroup))
    }

    func adopt() -> SelectedTaskSourceAdoption {
        XCTAssertTrue(journal.registerSourceDescriptors(in: [outer]))
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.isOrdinaryAdoption)
        // ComponentHost performs the existing M transition. The fixture never
        // advances M, prepares an individual facet, or records acceptance.
        let result = ComponentHost.reconcileChildren(
            of: fixture.runtime.root, oldChildren: fixture.runtime.root.children, newNodes: [outer],
            taskAdoption: context, lazyJournal: journal)
        let disposition = journal.seal(completedCheckedAdoption: result.completed)
        journal.finishAcceptedTaskCleanup()
        journal.releaseUnadoptedTransport()
        scope.finish()
        return SelectedTaskSourceAdoption(native: result, disposition: disposition)
    }
}

private final class SelectedTaskSourceActionLifetime: @unchecked Sendable {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    deinit {
        // The rejected proposal is released synchronously on the MainActor.
        // An unexpected Task retains this object and fails the pre-await oracle.
        MainActor.assumeIsolated { onRelease() }
    }
}

private struct SelectedTaskSourceRun: Equatable, Sendable {
    let number: Int
    let id: Int
    let wasCancelledAtEntry: Bool
}

/// Same cancellation-handler/continuation-ready discipline as the pinned
/// MountedTaskIDLifecycleProbe. No polling, retry, or scheduling-yield loops.
@MainActor
private final class SelectedTaskSourceProbe {
    private(set) var runs: [SelectedTaskSourceRun] = []
    private(set) var cancellations: [Int] = []
    private(set) var completions: [Int] = []
    var events: [String] = []
    var onReady: ((SelectedTaskSourceRun) -> Void)?
    var onCancelled: ((SelectedTaskSourceRun) -> Void)?
    var onCompleted: ((SelectedTaskSourceRun) -> Void)?
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isReleased = false

    var suspendedCount: Int { continuations.count }

    func run(id: Int) async {
        let run = SelectedTaskSourceRun(number: runs.count, id: id, wasCancelledAtEntry: Task.isCancelled)
        runs.append(run)
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
                    onReady?(run)
                }
            },
            onCancel: { [weak self] in
                let probe = self
                MainActor.assumeIsolated { probe?.cancel(run) }
            })
        completions.append(run.number)
        onCompleted?(run)
    }

    private func cancel(_ run: SelectedTaskSourceRun) {
        guard !cancellations.contains(run.number) else { return }
        cancellations.append(run.number)
        events.append("cancel-\(run.number)")
        let continuation = continuations.removeValue(forKey: run.number)
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
