import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Raw-node metadata fixtures for the existing controller adoption boundary.
/// Checked cases use the dormant adapter admission; they do not qualify native
/// editing, bindings, focus, UIA, layout settlement, or the public list facade.
@MainActor
final class RetainedLazyListTextInputMetadataTests: XCTestCase {
    func testCheckedRawMetadataRefreshCopiesCaretAndClearsNilSelection() async throws {
        let oldSelection = RetainedTextSelection(indices: .insertionPoint(1), affinity: .upstream)
        let selections: [RetainedTextSelection?] = [
            .init(indices: .range(1..<3), affinity: .downstream),
            nil,
        ]
        for selection in selections {
            // Each accepted variant owns a fresh candidate and admission.
            let retained = rawNode(caret: 1, selection: oldSelection)
            let incoming = rawNode(caret: 4, selection: selection)
            let fixture = try TextInputMetadataAdoptionFixture(retained: retained, incoming: incoming, checked: true)
            defer { fixture.finish() }
            let admission = try XCTUnwrap(fixture.admission)

            let result = fixture.reconcile()

            XCTAssertTrue(result.completed)
            XCTAssertTrue(result.didMutate)
            XCTAssertTrue(result.completion?.isCurrent == true)
            XCTAssertTrue(admission.isCurrent)
            XCTAssertEqual(result.children.count, 1)
            XCTAssertTrue(result.children.first === retained)
            XCTAssertTrue(retained.parent === fixture.container)
            XCTAssertTrue(retained.retainedLazyListRuntime === fixture.runtime)
            XCTAssertEqual(retained.textInputCaretOffset, 4)
            XCTAssertEqual(retained.textInputSelection, selection)
            XCTAssertNil(retained.textInputController)
            XCTAssertNil(incoming.textInputController)
            finishAndCheck(fixture)
        }
    }

    func testControllerDepartureCopiesMetadataAfterDetachInOrdinaryAndCheckedAdoption() async throws {
        let oldSelection = RetainedTextSelection(indices: .insertionPoint(1), affinity: .upstream)
        let incomingSelection = RetainedTextSelection(indices: .range(1..<3), affinity: .downstream)
        let detachSelection = RetainedTextSelection(indices: .range(6..<9), affinity: .upstream)
        for checked in [false, true] {
            let mode = checked ? "checked" : "ordinary"
            let retained = rawNode(caret: 1, selection: oldSelection)
            let incoming = rawNode(caret: 4, selection: incomingSelection)
            let fixture = try TextInputMetadataAdoptionFixture(retained: retained, incoming: incoming, checked: checked)
            defer { fixture.finish() }
            let controller = TextInputMetadataTestController()
            defer { controller.clearCallbacks() }
            retained.textInputController = controller
            var events: [String] = []
            var caretBeforeDetach: Int?
            var selectionBeforeDetach: RetainedTextSelection?
            var caretAtUpdate: Int?
            var selectionAtUpdate: RetainedTextSelection?
            var updateSawNoController = false
            controller.onDetach = { node in
                events.append("detach")
                caretBeforeDetach = node.textInputCaretOffset
                selectionBeforeDetach = node.textInputSelection
                node.textInputCaretOffset = 9
                node.textInputSelection = detachSelection
            }
            incoming.onUpdatePlatformView = { node in
                events.append("update")
                caretAtUpdate = node.textInputCaretOffset
                selectionAtUpdate = node.textInputSelection
                updateSawNoController = node.textInputController == nil
            }

            let result = fixture.reconcile()

            XCTAssertTrue(result.completed, mode)
            XCTAssertTrue(result.didMutate, mode)
            XCTAssertEqual(events, ["detach", "update"], mode)
            XCTAssertEqual(controller.detachCalls, 1, mode)
            XCTAssertEqual(controller.reconcileCalls, 0, mode)
            XCTAssertEqual(caretBeforeDetach, 1, mode)
            XCTAssertEqual(selectionBeforeDetach, oldSelection, mode)
            XCTAssertEqual(caretAtUpdate, 4, mode)
            XCTAssertEqual(selectionAtUpdate, incomingSelection, mode)
            XCTAssertTrue(updateSawNoController, mode)
            XCTAssertNil(retained.textInputController, mode)
            XCTAssertEqual(retained.textInputCaretOffset, 4, mode)
            XCTAssertEqual(retained.textInputSelection, incomingSelection, mode)
            XCTAssertTrue(result.children.first === retained, mode)
            if checked {
                XCTAssertTrue(try XCTUnwrap(fixture.admission).isCurrent)
            } else {
                XCTAssertNil(fixture.admission)
                XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.isBuilding)
            }
            finishAndCheck(fixture)
        }
    }

    func testIncomingControllerRemainsAuthoritativeWithAndWithoutAPreviousController() async throws {
        let oldSelection = RetainedTextSelection(indices: .insertionPoint(1), affinity: .upstream)
        let rawSelection = RetainedTextSelection(indices: .range(1..<3), affinity: .downstream)
        let controllerSelection = RetainedTextSelection(indices: .range(5..<7), affinity: .upstream)
        for checked in [false, true] {
            for hasPrevious in [false, true] {
                // Checked controls do not mutate their captured source. The
                // ordinary variant also proves the branch was chosen before
                // a controller callback can clear the source's controller.
                for clearsSource in checked ? [false] : [false, true] {
                    let variant = "checked=\(checked), previous=\(hasPrevious), clearsSource=\(clearsSource)"
                    let retained = rawNode(caret: 1, selection: oldSelection)
                    let incoming = rawNode(caret: 4, selection: rawSelection)
                    let fixture = try TextInputMetadataAdoptionFixture(
                        retained: retained, incoming: incoming, checked: checked)
                    defer { fixture.finish() }
                    let previous = hasPrevious ? TextInputMetadataTestController() : nil
                    let controller = TextInputMetadataTestController()
                    defer {
                        controller.clearCallbacks()
                        previous?.clearCallbacks()
                    }
                    retained.textInputController = previous
                    var events: [String] = []
                    var reconciledPrevious: (any RetainedTextInputController)?
                    var reconciledNode: ViewNode?
                    var caretAtUpdate: Int?
                    var selectionAtUpdate: RetainedTextSelection?
                    controller.onAttach = { _ in events.append("attach") }
                    controller.onReconcile = { oldController, node in
                        events.append("reconcile")
                        reconciledPrevious = oldController
                        reconciledNode = node
                        node.textInputCaretOffset = 7
                        node.textInputSelection = controllerSelection
                        if clearsSource { incoming.textInputController = nil }
                    }
                    incoming.textInputController = controller
                    incoming.onUpdatePlatformView = { node in
                        events.append("update")
                        caretAtUpdate = node.textInputCaretOffset
                        selectionAtUpdate = node.textInputSelection
                    }

                    let result = fixture.reconcile()

                    XCTAssertTrue(result.completed, variant)
                    XCTAssertTrue(result.didMutate, variant)
                    XCTAssertEqual(events, ["attach", "reconcile", "update"], variant)
                    XCTAssertEqual(controller.attachCalls, 1, variant)
                    XCTAssertEqual(controller.reconcileCalls, 1, variant)
                    XCTAssertEqual(controller.detachCalls, 0, variant)
                    XCTAssertTrue(reconciledNode === retained, variant)
                    if let previous {
                        XCTAssertTrue(reconciledPrevious === previous, variant)
                        XCTAssertEqual(previous.detachCalls, 0, variant)
                    } else {
                        XCTAssertNil(reconciledPrevious, variant)
                    }
                    XCTAssertTrue(retained.textInputController === controller, variant)
                    XCTAssertEqual(retained.textInputCaretOffset, 7, variant)
                    XCTAssertEqual(retained.textInputSelection, controllerSelection, variant)
                    XCTAssertEqual(caretAtUpdate, 7, variant)
                    XCTAssertEqual(selectionAtUpdate, controllerSelection, variant)
                    XCTAssertTrue(result.children.first === retained, variant)
                    if clearsSource {
                        XCTAssertNil(incoming.textInputController, variant)
                    } else {
                        XCTAssertTrue(incoming.textInputController === controller, variant)
                    }
                    if checked {
                        XCTAssertTrue(try XCTUnwrap(fixture.admission).isCurrent)
                    } else {
                        XCTAssertNil(fixture.admission)
                        XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.isBuilding)
                    }
                    finishAndCheck(fixture)
                }
            }
        }
    }

    func testInterruptedCheckedDeparturePreservesCallbackMetadataBeforeLaterProperties() async throws {
        let oldSelection = RetainedTextSelection(indices: .insertionPoint(1), affinity: .upstream)
        let rawSelection = RetainedTextSelection(indices: .range(1..<3), affinity: .downstream)
        let callbackSelection = RetainedTextSelection(indices: .range(6..<9), affinity: .upstream)
        for closesProvider in [true, false] {
            let interruption = closesProvider ? "close" : "reattach"
            let retained = rawNode(caret: 1, selection: oldSelection)
            let incoming = rawNode(caret: 4, selection: rawSelection)
            retained.textSelectability = .enabled
            incoming.textSelectability = .disabled
            let fixture = try TextInputMetadataAdoptionFixture(retained: retained, incoming: incoming, checked: true)
            defer { fixture.finish() }
            let admission = try XCTUnwrap(fixture.admission)
            let attachment = retained.captureLazyListAttachmentProof()
            let controller = TextInputMetadataTestController()
            defer { controller.clearCallbacks() }
            retained.textInputController = controller
            var events: [String] = []
            var didInterrupt = false
            var sawDetachedNode = false
            var updates = 0
            incoming.onUpdatePlatformView = { _ in updates += 1 }
            controller.onDetach = { node in
                // Removing a mounted node delivers another detach. Only the
                // outer callback performs the intentional remove/add cycle.
                guard !didInterrupt else { return }
                didInterrupt = true
                events.append("detach")
                node.textInputCaretOffset = 9
                node.textInputSelection = callbackSelection
                if closesProvider {
                    fixture.provider.close()
                } else {
                    fixture.container.removeChild(node)
                    sawDetachedNode = node.parent == nil && node.retainedLazyListRuntime == nil
                    fixture.container.addChild(node)
                }
                events.append(interruption)
            }

            let result = fixture.reconcile()

            XCTAssertFalse(result.completed, interruption)
            XCTAssertTrue(result.didMutate, interruption)
            XCTAssertNil(result.completion, interruption)
            XCTAssertFalse(admission.isCurrent, interruption)
            XCTAssertEqual(events, ["detach", interruption], interruption)
            XCTAssertTrue(didInterrupt, interruption)
            XCTAssertEqual(retained.textInputCaretOffset, 9, interruption)
            XCTAssertEqual(retained.textInputSelection, callbackSelection, interruption)
            XCTAssertEqual(retained.textSelectability, .enabled, interruption)
            XCTAssertEqual(updates, 0, interruption)
            XCTAssertTrue(retained.textInputController === controller, interruption)
            XCTAssertEqual(result.children.count, 1, interruption)
            XCTAssertTrue(result.children.first === retained, interruption)
            XCTAssertTrue(retained.parent === fixture.container, interruption)
            XCTAssertTrue(retained.retainedLazyListRuntime === fixture.runtime, interruption)
            if closesProvider {
                XCTAssertTrue(attachment.isCurrent)
                XCTAssertEqual(controller.detachCalls, 1)
            } else {
                XCTAssertTrue(sawDetachedNode)
                XCTAssertFalse(attachment.isCurrent)
                XCTAssertEqual(controller.detachCalls, 2)
            }
            finishAndCheck(fixture)
        }
    }

    func testOutgoingControllerCaptureDestructionRevokesBeforeFallbackMetadataCopies() async throws {
        let oldSelection = RetainedTextSelection(indices: .insertionPoint(1), affinity: .upstream)
        let rawSelection = RetainedTextSelection(indices: .range(1..<3), affinity: .downstream)
        let callbackSelection = RetainedTextSelection(indices: .range(6..<9), affinity: .upstream)
        let retained = rawNode(caret: 1, selection: oldSelection)
        let incoming = rawNode(caret: 4, selection: rawSelection)
        retained.textSelectability = .enabled
        incoming.textSelectability = .disabled
        let fixture = try TextInputMetadataAdoptionFixture(retained: retained, incoming: incoming, checked: true)
        defer { fixture.finish() }
        let admission = try XCTUnwrap(fixture.admission)
        var events: [String] = []
        var releaseSawNoController = false
        var releaseSawCurrentAdmission = false
        var caretAtRelease: Int?
        var selectionAtRelease: RetainedTextSelection?
        var updates = 0
        incoming.onUpdatePlatformView = { _ in updates += 1 }
        installReleaseObservedController(
            on: retained,
            onDetach: { node in
                events.append("detach")
                node.textInputCaretOffset = 9
                node.textInputSelection = callbackSelection
            },
            onRelease: {
                events.append("release")
                releaseSawNoController = retained.textInputController == nil
                releaseSawCurrentAdmission = admission.isCurrent
                caretAtRelease = retained.textInputCaretOffset
                selectionAtRelease = retained.textInputSelection
                fixture.provider.close()
            })
        XCTAssertTrue(events.isEmpty)
        XCTAssertNotNil(retained.textInputController)

        let result = fixture.reconcile()

        // These assertions precede fixture cleanup, so cleanup cannot supply
        // a missing release or turn a late destruction into a passing case.
        XCTAssertEqual(events, ["detach", "release"])
        XCTAssertTrue(releaseSawNoController)
        XCTAssertTrue(releaseSawCurrentAdmission)
        XCTAssertEqual(caretAtRelease, 9)
        XCTAssertEqual(selectionAtRelease, callbackSelection)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertNil(result.completion)
        XCTAssertFalse(admission.isCurrent)
        XCTAssertNil(retained.textInputController)
        XCTAssertEqual(retained.textInputCaretOffset, 9)
        XCTAssertEqual(retained.textInputSelection, callbackSelection)
        XCTAssertEqual(retained.textSelectability, .enabled)
        XCTAssertEqual(updates, 0)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === retained)
        XCTAssertTrue(retained.parent === fixture.container)
        XCTAssertTrue(retained.retainedLazyListRuntime === fixture.runtime)
        finishAndCheck(fixture)
        XCTAssertEqual(events, ["detach", "release"])
    }

    private func rawNode(caret: Int, selection: RetainedTextSelection?) -> ViewNode {
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 20), text: "metadata")
        node.textInputCaretOffset = caret
        node.textInputSelection = selection
        return node
    }

    private func installReleaseObservedController(
        on node: ViewNode, onDetach: @escaping (ViewNode) -> Void, onRelease: @escaping @MainActor () -> Void
    ) {
        // No setup-owned strong controller or payload reference escapes this
        // helper. The node's controller slot owns the capture at adoption.
        let controller = TextInputMetadataTestController()
        let payload = TextInputMetadataDeinitAction(onRelease)
        controller.onDetach = { [payload] node in
            onDetach(node)
            withExtendedLifetime(payload) {}
        }
        node.textInputController = controller
    }

    private func finishAndCheck(
        _ fixture: TextInputMetadataAdoptionFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        fixture.finish()
        XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.isBuilding, file: file, line: line)
        XCTAssertTrue(fixture.runtime.root.children.isEmpty, file: file, line: line)
        XCTAssertNil(fixture.retained.retainedLazyListRuntime, file: file, line: line)
        XCTAssertNil(fixture.incoming.retainedLazyListRuntime, file: file, line: line)
    }
}

@MainActor
private final class TextInputMetadataAdoptionFixture {
    let retained: ViewNode
    let incoming: ViewNode
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let container: ViewNode
    let runtime: RetainedViewRuntime
    let lease: TextInputMetadataTestLease
    let epoch: TextInputMetadataTestEpoch?
    let candidate: RetainedLazyListRuntimeAdapter.Candidate?
    let admission: RetainedLazyListAdoptionAdmission?
    private var finished = false

    init(retained: ViewNode, incoming: ViewNode, checked: Bool) throws {
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        guard
            provider.replaceData(
                [0], id: \.self, identityRoot: .init(segments: [.role(.content)]), rowContent: { _, _ in [incoming] })
        else { throw TextInputMetadataFixtureError.setup }
        let row = try XCTUnwrap(provider.metadata?.rows.first)
        let request = try XCTUnwrap(provider.request(for: row.token))
        let prefix = try XCTUnwrap(provider.identityPrefix(for: request))
        // Establish matching row identities before either node is mounted.
        let identity = prefix.appending(contentsOf: [.role(.content), .slot(0)])
        retained.retainedViewIdentity = identity
        incoming.retainedViewIdentity = identity
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60))
        container.addChild(retained)
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60)))
        runtime.root.addChild(container)
        let lease = TextInputMetadataTestLease()
        self.retained = retained
        self.incoming = incoming
        self.provider = provider
        self.adapter = adapter
        self.container = container
        self.runtime = runtime
        self.lease = lease
        guard checked else {
            self.epoch = nil
            self.candidate = nil
            self.admission = nil
            return
        }

        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 100, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 60))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let epoch = TextInputMetadataTestEpoch()
        coordinator.install(epoch, startedAt: sequence)
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: container, runtime: runtime,
            coordinator: coordinator, sequence: sequence)
        var setupCompleted = false
        defer {
            if !setupCompleted {
                epoch.abandon()
                epoch.finishAfterCallbacks()
                coordinator.finishBuild()
                provider.close()
                runtime.root.removeChild(container)
            }
        }
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget, admission: admission),
            admission.installCandidate(candidate), epoch.willAdopt(), admission.isCurrent
        else { throw TextInputMetadataFixtureError.setup }
        self.epoch = epoch
        self.candidate = candidate
        self.admission = admission
        setupCompleted = true
    }

    func reconcile() -> RetainedLazyListAdoptionResult {
        ComponentHost.reconcileChildren(
            of: container, oldChildren: container.children,
            newNodes: candidate?.children ?? [incoming], admission: admission)
    }

    func finish() {
        guard !finished else { return }
        finished = true
        provider.close()
        // Both objects remain reachable here even if an interrupted plan
        // abandons the source or a callback removes the retained node.
        for node in [retained, incoming] {
            (node.textInputController as? TextInputMetadataTestController)?.clearCallbacks()
            node.onUpdatePlatformView = nil
        }
        if let epoch, let admission {
            if admission.didMutate { epoch.commit() } else { epoch.abandon() }
            epoch.finishAfterCallbacks()
            runtime.retainedBuildCoordinator.finishBuild()
        }
        runtime.root.removeChild(container)
    }
}

private enum TextInputMetadataFixtureError: Error { case setup }

@MainActor
private final class TextInputMetadataTestLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { TextInputMetadataTestEpoch() }
}

@MainActor
private final class TextInputMetadataTestEpoch: RetainedBuildEpoch {
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

@MainActor
private final class TextInputMetadataTestController: RetainedTextInputController {
    var onAttach: ((ViewNode) -> Void)?
    var onReconcile: (((any RetainedTextInputController)?, ViewNode) -> Void)?
    var onDetach: ((ViewNode) -> Void)?
    private(set) var attachCalls = 0
    private(set) var reconcileCalls = 0
    private(set) var detachCalls = 0

    func attach(to node: ViewNode) {
        attachCalls += 1
        onAttach?(node)
    }
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        reconcileCalls += 1
        onReconcile?(previous, node)
    }
    func detach(from node: ViewNode) {
        detachCalls += 1
        onDetach?(node)
    }
    func clearCallbacks() {
        onAttach = nil
        onReconcile = nil
        onDetach = nil
    }
}

private final class TextInputMetadataDeinitAction {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    deinit { MainActor.assumeIsolated { [action] in action() } }
}
