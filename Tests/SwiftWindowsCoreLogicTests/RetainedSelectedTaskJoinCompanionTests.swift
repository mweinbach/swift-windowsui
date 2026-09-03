import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Additive native Task tests. The original source-adoption packet is unchanged.
/// All field and attachment facts come from normal ComponentHost reconciliation;
/// this fixture never manufactures an accepted facet or a source-adoption ticket.
@MainActor
final class RetainedSelectedTaskJoinCompanionTests: XCTestCase {
    func testAllOutputJoinWaitsForIncomingLeafAndKeepsTheUnchangedActualRoute() async throws {
        let probe = SelectedTaskCompanionProbe()
        let fixture = SelectedTaskCompanionFixture()
        defer { fixture.finish(probe: probe) }
        let mount = RetainedTaskMountToken()
        let original = try SelectedTaskCompanionOperation(
            fixture: fixture, selections: [1, 1], taskID: 1, mount: mount,
            action: { await probe.run(id: 1) })
        let firstReady = expectReady(probe, number: 0, id: 1, fixture: fixture, outputCount: 2)
        let firstAdoption = original.adopt()
        assertNativeCompletion(firstAdoption, operation: original, fixture: fixture)
        let firstActual = try fixture.installedNodes()
        XCTAssertEqual(firstActual.count, 2)
        for (actual, source) in zip(firstActual, original.sources) {
            XCTAssertTrue(actual.outer === source.outer)
            XCTAssertTrue(actual.inner === source.inner)
            XCTAssertTrue(actual.selected === source.selected)
        }
        assertTaskFacts(firstAdoption.disposition, operation: original, actual: firstActual)
        XCTAssertTrue(original.declaration.canCommit)
        original.declaration.deliver(restart: false)
        fixture.render()
        await fulfillment(of: [firstReady], timeout: 5)

        let before = try fixture.installedNodes()
        let unchanged = try XCTUnwrap(before.first)
        let changing = try XCTUnwrap(before.last)
        XCTAssertFalse(unchanged.outer === changing.outer)
        let unchangedOuterAttachment = unchanged.outer.captureLazyListAttachmentProof()
        let unchangedInnerAttachment = unchanged.inner.captureLazyListAttachmentProof()
        let unchangedSelectedAttachment = unchanged.selected.captureLazyListAttachmentProof()
        let oldSelectedAttachment = changing.selected.captureLazyListAttachmentProof()
        var unchangedDepartures = 0
        var pendingJoinCallbacks = 0
        unchanged.selected.onDismantlePlatformView = { _ in unchangedDepartures += 1 }
        changing.selected.onDisappear = {
            XCTAssertTrue(probe.cancellations.isEmpty)
            probe.events.append("old-disappear")
        }

        // Output zero matches at every level. Output one retains both boundary
        // objects, but its old selected leaf is replaced by a fresh incoming leaf.
        // Thus the native incoming forest excludes every retained actual object.
        let replacement = try SelectedTaskCompanionOperation(
            fixture: fixture, selections: [1, 2], taskID: 2, mount: mount,
            clearSelectedAttachmentsBeforeStaging: true,
            action: { await probe.run(id: 2) })
        let unchangedSource = try XCTUnwrap(replacement.sources.first)
        let incomingSource = try XCTUnwrap(replacement.sources.last)
        unchangedSource.selected.onDismantlePlatformView = { _ in unchangedDepartures += 1 }
        let nextDeclaration = replacement.declaration
        let nextContribution = replacement.taskContribution
        let originalDeclaration = original.declaration
        changing.selected.onDismantlePlatformView = { [weak oldSelected = changing.selected] actual in
            guard let oldSelected else { return }
            pendingJoinCallbacks += 1
            XCTAssertEqual(pendingJoinCallbacks, 1)
            XCTAssertTrue(actual === oldSelected)
            // ComponentHost has completed the first matched output before
            // descending into this later sibling. No initial join may consume
            // that first route while this second output still lacks its facts.
            XCTAssertFalse(nextDeclaration.canCommit)
            XCTAssertFalse(nextContribution.isActive)
            XCTAssertFalse(originalDeclaration.canCommit)
            XCTAssertTrue(probe.cancellations.isEmpty)
            XCTAssertEqual(probe.runs.map(\.id), [1])
            XCTAssertEqual(unchangedDepartures, 0)
            XCTAssertTrue(unchanged.outer.children.first === unchanged.inner)
            XCTAssertTrue(unchanged.inner.children.first === unchanged.selected)
            XCTAssertTrue(unchangedSelectedAttachment.isCurrent)
            XCTAssertFalse(unchangedSource.outer === unchanged.outer)
            XCTAssertFalse(unchangedSource.selected === unchanged.selected)
            XCTAssertTrue(unchangedSource.selected.parent === unchangedSource.inner)
            XCTAssertNil(unchangedSource.outer.retainedLazyListRuntime)
            XCTAssertTrue(incomingSource.selected.parent === incomingSource.inner)
            XCTAssertNil(incomingSource.selected.retainedLazyListRuntime)
        }
        let oldTerminal = expectTerminal(probe, number: 0, id: 1)
        let nextReady = expectReady(probe, number: 1, id: 2, fixture: fixture, outputCount: 2)
        let adoption = replacement.adopt()
        assertNativeCompletion(adoption, operation: replacement, fixture: fixture)
        XCTAssertEqual(pendingJoinCallbacks, 1)
        let after = try fixture.installedNodes()
        XCTAssertEqual(after.count, 2)
        let retained = try XCTUnwrap(after.first)
        let inserted = try XCTUnwrap(after.last)
        XCTAssertTrue(retained.outer === unchanged.outer)
        XCTAssertTrue(retained.inner === unchanged.inner)
        XCTAssertTrue(retained.selected === unchanged.selected)
        XCTAssertTrue(retained.outer.children.first === unchanged.inner)
        XCTAssertTrue(retained.inner.children.first === unchanged.selected)
        XCTAssertTrue(unchangedOuterAttachment.isCurrent)
        XCTAssertTrue(unchangedInnerAttachment.isCurrent)
        XCTAssertTrue(unchangedSelectedAttachment.isCurrent)
        XCTAssertEqual(unchangedDepartures, 0)
        XCTAssertTrue(inserted.outer === changing.outer)
        XCTAssertTrue(inserted.inner === changing.inner)
        XCTAssertTrue(inserted.selected === incomingSource.selected)
        XCTAssertFalse(inserted.selected === changing.selected)
        XCTAssertTrue(incomingSource.inner.children.isEmpty)
        XCTAssertTrue(incomingSource.selected.parent === changing.inner)
        XCTAssertFalse(oldSelectedAttachment.isCurrent)
        XCTAssertNil(changing.selected.parent)
        XCTAssertNil(changing.selected.retainedLazyListRuntime)
        // The unchanged source remains detached. Its actual mapping must not
        // be inferred as source=self merely because the target children match.
        XCTAssertTrue(unchangedSource.outer.children.first === unchangedSource.inner)
        XCTAssertTrue(unchangedSource.inner.children.first === unchangedSource.selected)
        XCTAssertTrue(unchangedSource.selected.parent === unchangedSource.inner)
        XCTAssertNil(unchangedSource.selected.retainedLazyListRuntime)
        assertTaskFacts(adoption.disposition, operation: replacement, actual: after)
        XCTAssertTrue(replacement.declaration.canCommit)
        replacement.declaration.deliver(restart: true)
        fixture.render()

        await fulfillment(of: oldTerminal + [nextReady], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.id), [1, 2])
        XCTAssertEqual(probe.cancellations, [0])
        XCTAssertEqual(probe.completions, [0])
        XCTAssertEqual(probe.suspendedCount, 1)
        let disappeared = try XCTUnwrap(probe.events.firstIndex(of: "old-disappear"))
        let cancelled = try XCTUnwrap(probe.events.firstIndex(of: "cancel-0"))
        XCTAssertLessThan(disappeared, cancelled)
        XCTAssertTrue(unchangedSelectedAttachment.isCurrent)
        XCTAssertEqual(unchangedDepartures, 0)

        let lastTerminal = expectTerminal(probe, number: 1, id: 2)
        fixture.runtime.root.removeAllChildren()
        await fulfillment(of: lastTerminal, timeout: 5)
        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertFalse(replacement.declaration.canCommit)
        XCTAssertNil(retained.outer.parent)
        XCTAssertNil(inserted.outer.parent)
        XCTAssertNil(retained.selected.retainedLazyListRuntime)
        XCTAssertNil(inserted.selected.retainedLazyListRuntime)
        XCTAssertEqual(probe.cancellations, [0, 1])
        XCTAssertEqual(probe.completions, [0, 1])
        XCTAssertEqual(probe.suspendedCount, 0)
        XCTAssertTrue(fixture.runtime.permitsRetainedActionInvocation)
    }

    func testSourceInferredForeignNilRevokeRefusesTaskWithoutChangingTheOrdinaryReplacement() async throws {
        let probe = SelectedTaskCompanionProbe()
        let fixture = SelectedTaskCompanionFixture()
        defer { fixture.finish(probe: probe) }
        let original = try SelectedTaskCompanionOperation(
            fixture: fixture, selections: [1], taskID: 1, mount: RetainedTaskMountToken(),
            action: { await probe.run(id: 1) })
        let ready = expectReady(probe, number: 0, id: 1, fixture: fixture, outputCount: 1)
        let firstAdoption = original.adopt()
        assertNativeCompletion(firstAdoption, operation: original, fixture: fixture)
        original.declaration.deliver(restart: false)
        fixture.render()
        await fulfillment(of: [ready], timeout: 5)
        let old = try XCTUnwrap(fixture.installedNodes().first)
        old.selected.onDisappear = {
            XCTAssertTrue(probe.cancellations.isEmpty)
            probe.events.append("old-disappear")
        }
        let terminal = expectTerminal(probe, number: 0, id: 1)
        var actionReleases = 0

        let refused = try performForeignNilRevoke(
            fixture: fixture, probe: probe, original: original.declaration,
            old: old, onActionRelease: { actionReleases += 1 })
        // Before any actor suspension, an unexpected Task would still retain
        // the action while waiting to enter the MainActor probe. Positive
        // release therefore checks that no replacement attempt was created.
        XCTAssertEqual(actionReleases, 1)
        XCTAssertEqual(refused.callbackCount, 1)
        XCTAssertTrue(refused.nativeCompleted)
        XCTAssertTrue(refused.nativeDidMutate)
        XCTAssertTrue(refused.normalContributionIsActive)
        XCTAssertEqual(refused.acceptedTaskGroups, 0)
        let actual = try XCTUnwrap(fixture.installedNodes().first)
        XCTAssertTrue(actual.outer === old.outer)
        XCTAssertTrue(actual.inner === old.inner)
        XCTAssertTrue(actual.selected === refused.selected)
        XCTAssertEqual(actual.selected.accessibilityIdentifier, "companion-source-0-2")
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
    private func performForeignNilRevoke(
        fixture: SelectedTaskCompanionFixture, probe: SelectedTaskCompanionProbe,
        original: RetainedTaskDeclaration, old: SelectedTaskCompanionNodes,
        onActionRelease: @escaping @MainActor () -> Void
    ) throws -> SelectedTaskCompanionRefusal {
        let actionLifetime = SelectedTaskCompanionActionLifetime(onRelease: onActionRelease)
        let operation = try SelectedTaskCompanionOperation(
            fixture: fixture, selections: [2], taskID: 2, mount: RetainedTaskMountToken(),
            clearSelectedAttachmentsBeforeStaging: true,
            action: {
                await probe.run(id: 2)
                withExtendedLifetime(actionLifetime) {}
            })
        let source = try XCTUnwrap(operation.sources.first)
        let originalPath = try XCTUnwrap(operation.constructionPaths.first)
        var callbackCount = 0
        old.selected.onDismantlePlatformView = { [weak sourceInner = source.inner, weak selected = source.selected] _ in
            guard let sourceInner, let selected else { return }
            callbackCount += 1
            XCTAssertEqual(callbackCount, 1)
            XCTAssertFalse(original.canCommit)
            XCTAssertTrue(probe.cancellations.isEmpty)
            XCTAssertTrue(originalPath.isCurrent)
            XCTAssertEqual(sourceInner.children.count, 1)
            XCTAssertTrue(sourceInner.children.first === selected)
            XCTAssertTrue(selected.parent === sourceInner)
            XCTAssertNil(selected.retainedLazyListRuntime)
            // SOURCE-DERIVED precondition, not a runtime observation of nil:
            // the fixture's literal nil clear preceded path capture/staging;
            // the pinned ordinary preparation path mints no source lazy proof
            // before this OLD actual child's callback. See REPORT.md. Never
            // call captureLazyListAttachmentProof here: it would change nil.
            // This is one real foreign revoke, with no child/parent/runtime
            // mutation and no Task transfer ticket passed to the native writer.
            XCTAssertNil(selected.revokeLazyListAttachmentProofs(removalWrite: nil))
            XCTAssertTrue(originalPath.isCurrent)
            XCTAssertEqual(sourceInner.children.count, 1)
            XCTAssertTrue(sourceInner.children.first === selected)
            XCTAssertTrue(selected.parent === sourceInner)
            XCTAssertNil(selected.retainedLazyListRuntime)
        }

        let adoption = operation.adopt()
        assertNativeCompletion(adoption, operation: operation, fixture: fixture)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertFalse(operation.declaration.canCommit)
        XCTAssertFalse(operation.taskContribution.isActive)
        operation.declaration.deliver(restart: false)
        fixture.render()
        XCTAssertFalse(source.selected.existingRetainedTaskState?.hasCommittedSlots ?? false)
        let taskGroups = adoption.disposition.acceptedOrdinaryGroups.filter {
            $0.proposal.group === operation.taskGroup
        }
        XCTAssertTrue(taskGroups.isEmpty)
        withExtendedLifetime((operation, originalPath)) {}
        return SelectedTaskCompanionRefusal(
            selected: source.selected, callbackCount: callbackCount,
            nativeCompleted: adoption.native.completed, nativeDidMutate: adoption.native.didMutate,
            normalContributionIsActive: operation.normalContribution.isActive,
            acceptedTaskGroups: taskGroups.count)
    }

    private func assertNativeCompletion(
        _ adoption: SelectedTaskCompanionAdoption, operation: SelectedTaskCompanionOperation,
        fixture: SelectedTaskCompanionFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(adoption.native.completed, file: file, line: line)
        XCTAssertTrue(adoption.native.didMutate, file: file, line: line)
        XCTAssertEqual(adoption.disposition.stop, .completedCheckedAdoption, file: file, line: line)
        XCTAssertTrue(operation.normalContribution.isActive, file: file, line: line)
        XCTAssertEqual(
            adoption.disposition.acceptedOrdinaryGroups.filter { $0.proposal.group === operation.normalGroup }.count,
            1, file: file, line: line)
        XCTAssertEqual(fixture.runtime.root.children.count, operation.sources.count, file: file, line: line)
        XCTAssertTrue(fixture.runtime.permitsRetainedActionInvocation, file: file, line: line)
    }

    private func assertTaskFacts(
        _ disposition: RetainedLazyListAdoptionDisposition, operation: SelectedTaskCompanionOperation,
        actual: [SelectedTaskCompanionNodes], file: StaticString = #filePath, line: UInt = #line
    ) {
        let accepted = disposition.acceptedOrdinaryGroups.filter { $0.proposal.group === operation.taskGroup }
        XCTAssertEqual(accepted.count, 1, file: file, line: line)
        guard let group = accepted.first else { return }
        XCTAssertTrue(group.receipt.isActive, file: file, line: line)
        XCTAssertEqual(
            Set(group.acceptedFacets.map { ObjectIdentifier($0.source) }).count,
            operation.payloads.count, file: file, line: line)
        XCTAssertEqual(actual.count, operation.payloads.count, file: file, line: line)
        for (payload, nodes) in zip(operation.payloads, actual) {
            let facts = group.acceptedFacets.filter { $0.source === payload }
            var attachments: [ViewNode] = []
            var hooks = 0
            var declarations = 0
            for fact in facts {
                XCTAssertTrue(fact.actual.isAttached, file: file, line: line)
                switch fact.nativeField {
                case .childAttachment:
                    if let node = fact.actual.node { attachments.append(node) }
                case .nodeProperty(let keyPath):
                    XCTAssertTrue(
                        keyPath == \ViewNode.onAppearWithNode || keyPath == \ViewNode.onDisappearWithNode,
                        file: file, line: line)
                    XCTAssertTrue(fact.actual.node === nodes.selected, file: file, line: line)
                    hooks += 1
                case .scopedTaskDeclaration(let declaration):
                    XCTAssertTrue(declaration === operation.declaration.declarationID, file: file, line: line)
                    XCTAssertTrue(fact.actual.node === nodes.selected, file: file, line: line)
                    declarations += 1
                default:
                    XCTFail("A routed Task received an unrelated native facet", file: file, line: line)
                }
            }
            XCTAssertEqual(attachments.count, 2, file: file, line: line)
            XCTAssertTrue(attachments.contains { $0 === nodes.outer }, file: file, line: line)
            XCTAssertTrue(attachments.contains { $0 === nodes.inner }, file: file, line: line)
            XCTAssertEqual(hooks, 2, file: file, line: line)
            XCTAssertEqual(declarations, 1, file: file, line: line)
        }
    }

    private func expectReady(
        _ probe: SelectedTaskCompanionProbe, number: Int, id: Int, fixture: SelectedTaskCompanionFixture,
        outputCount: Int
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
                XCTAssertEqual(actual.count, outputCount)
                for nodes in actual {
                    XCTAssertTrue(nodes.selected.hasAppeared)
                    XCTAssertTrue(nodes.selected.parent === nodes.inner)
                    XCTAssertTrue(nodes.inner.parent === nodes.outer)
                    XCTAssertNotNil(nodes.selected.onAppearWithNode)
                    XCTAssertNotNil(nodes.selected.onDisappearWithNode)
                    XCTAssertNil(nodes.outer.onAppearWithNode)
                    XCTAssertNil(nodes.outer.onDisappearWithNode)
                    XCTAssertNil(nodes.inner.onAppearWithNode)
                    XCTAssertNil(nodes.inner.onDisappearWithNode)
                    XCTAssertFalse(nodes.outer.existingRetainedTaskState?.hasCommittedSlots ?? false)
                    XCTAssertFalse(nodes.inner.existingRetainedTaskState?.hasCommittedSlots ?? false)
                }
                XCTAssertEqual(probe.suspendedCount, 1)
            } catch {
                XCTFail("Entered Task must belong to every installed selected node: \(error)")
            }
        }
        return ready
    }

    private func expectTerminal(
        _ probe: SelectedTaskCompanionProbe, number: Int, id: Int
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

@MainActor
private struct SelectedTaskCompanionNodes {
    let outer: ViewNode
    let inner: ViewNode
    let selected: ViewNode
}

@MainActor
private struct SelectedTaskCompanionAdoption {
    let native: RetainedLazyListAdoptionResult
    let disposition: RetainedLazyListAdoptionDisposition
}

@MainActor
private final class SelectedTaskCompanionEpoch: RetainedBuildEpoch {
    var canAdopt = true
    var canComplete = true
    func supersede() { canAdopt = false }
    func willAdopt() -> Bool { canAdopt }
    func commit() {}
    func abandon() { canAdopt = false }
    func finishAfterCallbacks() {}
}

@MainActor
private struct SelectedTaskCompanionRefusal {
    let selected: ViewNode
    let callbackCount: Int
    let nativeCompleted: Bool
    let nativeDidMutate: Bool
    let normalContributionIsActive: Bool
    let acceptedTaskGroups: Int
}

@MainActor
private final class SelectedTaskCompanionFixture {
    let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 240, height: 80)))
    let epoch = SelectedTaskCompanionEpoch()
    private var isClosed = false

    func installedNodes() throws -> [SelectedTaskCompanionNodes] {
        try runtime.root.children.map { outer in
            XCTAssertEqual(outer.selectedContentRole, .viewThatFits)
            XCTAssertEqual(outer.children.count, 1)
            let inner = try XCTUnwrap(outer.children.first)
            XCTAssertEqual(inner.selectedContentRole, .viewThatFits)
            XCTAssertEqual(inner.children.count, 1)
            let selected = try XCTUnwrap(inner.children.first)
            XCTAssertNil(selected.selectedContentRole)
            return SelectedTaskCompanionNodes(outer: outer, inner: inner, selected: selected)
        }
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

    func finish(probe: SelectedTaskCompanionProbe) {
        probe.clearAcknowledgements()
        close()
        probe.releaseAll()
    }
}

@MainActor
private final class SelectedTaskCompanionOperation {
    let sources: [SelectedTaskCompanionNodes]
    let constructionPaths: [RetainedSelectedContentPath]
    let payloads: [RetainedLazyListSourcePayloadID]
    let declaration: RetainedTaskDeclaration
    let taskGroup: RetainedDescriptorGroupID
    let taskContribution: RetainedDescriptorContributionReceipt
    let normalGroup: RetainedDescriptorGroupID
    let normalContribution: RetainedDescriptorContributionReceipt
    private let fixture: SelectedTaskCompanionFixture
    private let scope: RetainedLazyListDescriptorBuildScope
    private let journal: RetainedLazyListAdoptionJournal
    private let context: RetainedTaskAdoptionContext

    init(
        fixture: SelectedTaskCompanionFixture, selections: [Int], taskID: Int, mount: RetainedTaskMountToken,
        clearSelectedAttachmentsBeforeStaging: Bool = false,
        action: @escaping @Sendable () async -> Void
    ) throws {
        self.fixture = fixture
        let sources = selections.enumerated().map { index, selection in
            let selected = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 24))
            selected.retainedViewIdentity = RetainedViewIdentity().appending(.slot(selection))
            selected.accessibilityIdentifier = "companion-source-\(index)-\(selection)"
            let inner = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)
            inner.retainedViewIdentity = RetainedViewIdentity().appending(.slot(20))
            inner.frame = Rect(x: 0, y: 0, width: 100, height: 24)
            let outer = ViewNode.selectedContentBoundary(role: .viewThatFits, child: inner)
            outer.retainedViewIdentity = RetainedViewIdentity().appending(.slot(10 + index))
            outer.frame = Rect(x: index == 0 ? 0 : 110, y: 0, width: 100, height: 24)
            return SelectedTaskCompanionNodes(outer: outer, inner: inner, selected: selected)
        }
        self.sources = sources
        if clearSelectedAttachmentsBeforeStaging {
            for source in sources {
                XCTAssertNil(source.selected.retainedLazyListRuntime)
                XCTAssertTrue(source.selected.parent === source.inner)
                // Establish a known literal nil before any original path or
                // Task registration exists. No private field is assigned and
                // no attachment getter/proof capture is used by this setup.
                XCTAssertNil(source.selected.revokeLazyListAttachmentProofs(removalWrite: nil))
            }
        }
        let paths = try sources.map { try XCTUnwrap($0.outer.captureSelectedContentConstructionPath()) }
        constructionPaths = paths
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
                groupSources: sources.map(\.outer), in: fixture.runtime, descriptorAttribution: attribution,
                group: taskGroup, selectedContentPaths: paths, candidateConstruction: nil),
            "Task \(taskID) must stage every original physical output and selected path")
        for source in sources {
            source.selected.onAppearWithNode = { [weak declaration] actual in declaration?.appear(on: actual) }
            source.selected.onDisappearWithNode = { [weak declaration] actual in declaration?.disappear(from: actual) }
            XCTAssertTrue(attribution.recordSourceOutput(source.outer, group: taskGroup))
        }
        // A duplicate normal source registration returns the SAME original
        // payload. It does not supply a fake output or an accepted native fact.
        let payloads = try sources.map {
            try XCTUnwrap(attribution.recordTaskSourceOutput($0.outer, group: taskGroup))
        }
        self.payloads = payloads
        XCTAssertEqual(Set(payloads.map(ObjectIdentifier.init)).count, sources.count)
        taskContribution = try XCTUnwrap(attribution.contribution(for: taskGroup))
        _ = try XCTUnwrap(attribution.closeGroup(taskGroup))
        let normalGroup = try XCTUnwrap(attribution.registerGroup(kind: .structure))
        self.normalGroup = normalGroup
        for source in sources { XCTAssertTrue(attribution.recordSourceOutput(source.outer, group: normalGroup)) }
        normalContribution = try XCTUnwrap(attribution.contribution(for: normalGroup))
        _ = try XCTUnwrap(attribution.closeGroup(normalGroup))
    }

    func adopt() -> SelectedTaskCompanionAdoption {
        XCTAssertTrue(journal.registerSourceDescriptors(in: sources.map(\.outer)))
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.isOrdinaryAdoption)
        let result = ComponentHost.reconcileChildren(
            of: fixture.runtime.root, oldChildren: fixture.runtime.root.children, newNodes: sources.map(\.outer),
            taskAdoption: context, lazyJournal: journal)
        let disposition = journal.seal(completedCheckedAdoption: result.completed)
        journal.finishAcceptedTaskCleanup()
        journal.releaseUnadoptedTransport()
        scope.finish()
        return SelectedTaskCompanionAdoption(native: result, disposition: disposition)
    }
}

private final class SelectedTaskCompanionActionLifetime: @unchecked Sendable {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    deinit {
        // The rejected proposal is released synchronously on the MainActor.
        // An unexpected Task retains this object and fails the pre-await oracle.
        MainActor.assumeIsolated { onRelease() }
    }
}

private struct SelectedTaskCompanionRun: Equatable, Sendable {
    let number: Int
    let id: Int
    let wasCancelledAtEntry: Bool
}

/// Same cancellation-handler/continuation-ready discipline as the pinned
/// MountedTaskIDLifecycleProbe. No polling, retry, or scheduling-yield loops.
@MainActor
private final class SelectedTaskCompanionProbe {
    private(set) var runs: [SelectedTaskCompanionRun] = []
    private(set) var cancellations: [Int] = []
    private(set) var completions: [Int] = []
    var events: [String] = []
    var onReady: ((SelectedTaskCompanionRun) -> Void)?
    var onCancelled: ((SelectedTaskCompanionRun) -> Void)?
    var onCompleted: ((SelectedTaskCompanionRun) -> Void)?
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isReleased = false

    var suspendedCount: Int { continuations.count }

    func run(id: Int) async {
        let run = SelectedTaskCompanionRun(number: runs.count, id: id, wasCancelledAtEntry: Task.isCancelled)
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

    private func cancel(_ run: SelectedTaskCompanionRun) {
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
