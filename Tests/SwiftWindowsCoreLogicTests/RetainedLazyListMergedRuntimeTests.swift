import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// These headless fixtures combine checked lazy adoption with the retained
/// focus, presentation receipt, and physical accessibility attachment paths.
/// They do not enable public List construction or logical UIA providers, and
/// runtime focus exhaustion remains unexecuted. Editor ownership uses a test double.
@MainActor
final class RetainedLazyListMergedRuntimeTests: XCTestCase {
    func testReceiptReplacementReentrySeesEveryRetiringOwnerRevoked() async throws {
        let first = row("first", y: 0)
        let descendant = row("descendant", y: 0)
        descendant.isHitTestVisible = false
        first.addChild(descendant)
        let second = row("second", y: 40)
        first.isFocusable = true
        let nodes = [first, descendant, second]
        let editors = nodes.map { node in
            let editor = MergedRuntimeTextController()
            node.textInputController = editor
            return editor
        }
        var pointerDowns = 0
        var pointerExits = 0
        var pointerCancellations = 0
        var focusExits = 0
        var activations = 0
        var events: [String] = []
        first.onPointerDown = { pointerDowns += 1 }
        first.onPointerExit = { pointerExits += 1 }
        first.onPointerUpOutside = { pointerCancellations += 1 }
        first.onFocusExit = { focusExits += 1 }
        first.onActivate = { activations += 1 }
        let fixture = try MergedRuntimeFixture(previous: [first, second], incoming: []) { runtime in
            runtime.pointerDown(at: Point(x: 5, y: 5))
            XCTAssertEqual(pointerDowns, 1)
            XCTAssertTrue(first.isHovered)
            XCTAssertTrue(runtime.focusedNode === first)
        }
        defer { fixture.finish() }
        let proofs = nodes.map { $0.captureLazyListAttachmentProof() }
        let dialogs = nodes.map { $0.beginFileDialogPresentation(kind: .importer) }
        XCTAssertTrue(proofs.allSatisfy(\.isCurrent))
        XCTAssertTrue(dialogs.allSatisfy(\.isValid))
        XCTAssertTrue(zip(editors, nodes).allSatisfy { $0.0.isAuthorized(for: $0.1) })
        XCTAssertTrue(nodes.allSatisfy(\.hasAppeared))
        XCTAssertTrue(nodes.allSatisfy { fixture.runtime.accessibilityTarget(for: $0) != nil })
        let owner = MergedRuntimePresentationOwner()
        let released = MergedRuntimeReleaseObserver()
        let assertRevoked: @MainActor (String) -> Void = { phase in
            events.append(phase)
            XCTAssertTrue(proofs.allSatisfy { !$0.isCurrent })
            XCTAssertTrue(dialogs.allSatisfy { !$0.isValid })
            XCTAssertTrue(zip(editors, nodes).allSatisfy { !$0.0.isAuthorized(for: $0.1) })
            XCTAssertTrue(nodes.allSatisfy { fixture.runtime.accessibilityTarget(for: $0) == nil })
            XCTAssertTrue(nodes.allSatisfy { !$0.isFileDialogPresenter(in: fixture.runtime) })
            XCTAssertTrue(nodes.allSatisfy { !$0.hasAppeared })
            XCTAssertNil(first.parent)
            XCTAssertNil(second.parent)
            XCTAssertTrue(descendant.parent === first)
            XCTAssertTrue(fixture.container.children.isEmpty)
            XCTAssertFalse(first.isHovered)
            XCTAssertFalse(first.isFocused)
            XCTAssertNil(fixture.runtime.focusedNode)
            // Public cancellation must find no old private pointer owner.
            // Its already-captured cleanup still runs exactly once afterward.
            XCTAssertEqual(pointerExits, 0)
            XCTAssertEqual(pointerCancellations, 0)
            XCTAssertEqual(focusExits, 0)
            fixture.runtime.pointerCancelled()
            XCTAssertEqual(pointerExits, 0)
            XCTAssertEqual(pointerCancellations, 0)
            XCTAssertEqual(focusExits, 0)
        }
        do {
            let payload = MergedRuntimeReleasePayload { assertRevoked("capture release") }
            released.payload = payload
            fixture.runtime.schedulePresentationFocusRestoration(
                RetainedPresentationFocusRequest(
                    owner: owner, preferred: nil, underlyingModal: nil,
                    expectedFocusRevision: fixture.runtime.presentationFocusRevision,
                    isCurrent: { [payload] in withExtendedLifetime(payload) { true } },
                    resolveBase: { [weak root = fixture.runtime.root] in root },
                    didFinish: { assertRevoked("receipt finish") }))
        }
        XCTAssertNotNil(released.payload)
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(fixture.initialBuild.admission.isCurrent)
        var replacementFinishes = 0
        editors[0].onWillDetach = {
            events.append("first willDetach")
            fixture.runtime.schedulePresentationFocusRestoration(
                RetainedPresentationFocusRequest(
                    owner: owner, preferred: nil, underlyingModal: nil,
                    expectedFocusRevision: fixture.runtime.presentationFocusRevision,
                    isCurrent: { false }, resolveBase: { nil },
                    didFinish: { replacementFinishes += 1 }))
            XCTAssertNil(released.payload)
            XCTAssertEqual(events, ["first willDetach", "receipt finish", "capture release"])
        }

        let result = fixture.initialBuild.replace()

        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertTrue(result.children.isEmpty)
        XCTAssertEqual(events, ["first willDetach", "receipt finish", "capture release"])
        XCTAssertEqual(editors.map(\.revokeCalls), [1, 1, 1])
        XCTAssertEqual(editors.map(\.willDetachCalls), [1, 1, 1])
        XCTAssertEqual(editors.map(\.detachCalls), [1, 1, 1])
        XCTAssertEqual(pointerExits, 1)
        XCTAssertEqual(pointerCancellations, 1)
        XCTAssertEqual(focusExits, 1)
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(replacementFinishes, 0, "The replacement remains pending during the real build")
        XCTAssertTrue(fixture.initialBuild.finish(result))
        XCTAssertEqual(replacementFinishes, 1)
        XCTAssertNil(released.payload)
    }

    func testRetirementCleanupAndFocusExitPreserveTheNewestSurvivingFocus() async throws {
        let departing = row("departing")
        let cleanupFocus = row("cleanup focus", y: 100)
        let exitFocus = row("exit focus", y: 140)
        for node in [departing, cleanupFocus, exitFocus] { node.isFocusable = true }
        let editor = MergedRuntimeTextController()
        departing.textInputController = editor
        let fixture = try MergedRuntimeFixture(
            previous: [departing], incoming: [], outside: [cleanupFocus, exitFocus],
            beforeAdmission: { $0.requestFocus(departing) })
        defer { fixture.finish() }
        XCTAssertTrue(fixture.runtime.focusedNode === departing)
        let previousRevision = fixture.runtime.presentationFocusRevision
        var notifications: [String] = []
        var events: [String] = []
        fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.nodeTag ?? "nil") }
        editor.onWillDetach = {
            events.append("willDetach")
            XCTAssertNil(fixture.runtime.focusedNode)
            fixture.runtime.requestFocus(cleanupFocus)
            XCTAssertTrue(fixture.runtime.focusedNode === cleanupFocus)
        }
        cleanupFocus.onFocusExit = { events.append("cleanup focus exit") }
        departing.onFocusExit = {
            events.append("departing focus exit")
            XCTAssertTrue(fixture.runtime.focusedNode === cleanupFocus)
            fixture.runtime.requestFocus(exitFocus)
        }

        let result = fixture.initialBuild.replace()

        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(events, ["willDetach", "departing focus exit", "cleanup focus exit"])
        XCTAssertEqual(notifications, ["cleanup focus", "exit focus"])
        XCTAssertGreaterThan(fixture.runtime.presentationFocusRevision, previousRevision)
        XCTAssertTrue(fixture.runtime.focusedNode === exitFocus)
        XCTAssertTrue(exitFocus.isFocused)
        XCTAssertFalse(cleanupFocus.isFocused)
        XCTAssertFalse(departing.isFocused)
        XCTAssertTrue(cleanupFocus.parent === fixture.runtime.root)
        XCTAssertTrue(exitFocus.parent === fixture.runtime.root)
        XCTAssertNil(departing.parent)
        XCTAssertTrue(fixture.initialBuild.finish(result))
        XCTAssertEqual(notifications, ["cleanup focus", "exit focus"])
    }

    func testCheckedDetachAndReattachCannotReviveBorrowedAccessibilityTargets() async throws {
        let retained = row("retained")
        let descendant = row("descendant")
        retained.addChild(descendant)
        var borrowed: [RetainedAccessibilityTarget] = []
        let fixture = try MergedRuntimeFixture(previous: [retained], incoming: []) { runtime in
            let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
            defer { runtime.endAccessibilityMutation(mutation) }
            borrowed = try [retained, descendant].map { try XCTUnwrap(runtime.accessibilityTarget(for: $0)) }
            XCTAssertTrue(borrowed.allSatisfy { runtime.isAccessibilityTargetCurrent($0, during: mutation) })
        }
        defer { fixture.finish() }
        let attachments = [retained, descendant].map { $0.captureLazyListAttachmentProof() }

        let detached = fixture.initialBuild.replace()

        XCTAssertTrue(detached.completed)
        XCTAssertTrue(detached.didMutate)
        XCTAssertTrue(detached.children.isEmpty)
        XCTAssertNil(retained.parent)
        XCTAssertTrue(descendant.parent === retained)
        XCTAssertNil(fixture.runtime.accessibilityTarget(for: retained))
        XCTAssertNil(fixture.runtime.accessibilityTarget(for: descendant))
        XCTAssertTrue(attachments.allSatisfy { !$0.isCurrent })
        XCTAssertTrue(fixture.initialBuild.finish(detached))

        // A second genuine candidate and epoch attach the same physical tree.
        // The descendant never changes its immediate parent in either round.
        let nextBuild = try fixture.prepareNext(incoming: [retained])
        let attached = nextBuild.replace()

        XCTAssertTrue(attached.completed)
        XCTAssertTrue(attached.didMutate)
        XCTAssertEqual(attached.children.count, 1)
        XCTAssertTrue(attached.children.first === retained)
        XCTAssertTrue(retained.parent === fixture.container)
        XCTAssertTrue(retained.children.first === descendant)
        XCTAssertTrue(descendant.parent === retained)
        XCTAssertTrue(nextBuild.finish(attached))
        XCTAssertTrue(fixture.runtime.retainedBuildCoordinator.isBuildSettled)

        let mutation = try XCTUnwrap(fixture.runtime.beginAccessibilityMutation())
        defer { fixture.runtime.endAccessibilityMutation(mutation) }
        let fresh = try [retained, descendant].map { try XCTUnwrap(fixture.runtime.accessibilityTarget(for: $0)) }
        XCTAssertEqual(borrowed.count, 2)
        XCTAssertEqual(fresh.count, 2)
        XCTAssertTrue(fixture.runtime.isAccessibilityMutationCurrent(mutation))
        XCTAssertTrue(fresh.allSatisfy { fixture.runtime.isAccessibilityTargetCurrent($0, during: mutation) })
        XCTAssertTrue(borrowed.allSatisfy { !fixture.runtime.isAccessibilityTargetCurrent($0, during: mutation) })
        XCTAssertTrue(attachments.allSatisfy { !$0.isCurrent })
        XCTAssertTrue([retained, descendant].allSatisfy { $0.captureLazyListAttachmentProof().isCurrent })
    }

    func testCheckedAdoptionCopiesAndResetsCaretMarkerOnTheSamePhysicalNode() async throws {
        let retained = row("same slot")
        retained.text = "old label"
        let caretSource = row("same slot")
        caretSource.isTextInputCaret = true
        let fixture = try MergedRuntimeFixture(previous: [retained], incoming: [caretSource])
        defer { fixture.finish() }
        let originalAttachment = retained.captureLazyListAttachmentProof()
        XCTAssertFalse(retained.isTextInputCaret)

        let copied = fixture.initialBuild.reconcile()

        XCTAssertTrue(copied.completed)
        XCTAssertTrue(copied.didMutate)
        XCTAssertEqual(copied.children.count, 1)
        XCTAssertTrue(copied.children.first === retained)
        XCTAssertFalse(caretSource === retained)
        XCTAssertTrue(retained.isTextInputCaret)
        XCTAssertNil(retained.text)
        XCTAssertTrue(originalAttachment.isCurrent)
        XCTAssertTrue(copied.completion?.isCurrent == true)
        XCTAssertTrue(fixture.initialBuild.finish(copied))

        let labelSource = row("same slot")
        labelSource.text = "restored label"
        XCTAssertFalse(labelSource.isTextInputCaret)
        let nextBuild = try fixture.prepareNext(incoming: [labelSource])
        let reset = nextBuild.reconcile()

        XCTAssertTrue(reset.completed)
        XCTAssertTrue(reset.didMutate)
        XCTAssertEqual(reset.children.count, 1)
        XCTAssertTrue(reset.children.first === retained)
        XCTAssertFalse(labelSource === retained)
        XCTAssertFalse(retained.isTextInputCaret)
        XCTAssertEqual(retained.text, "restored label")
        XCTAssertTrue(retained.parent === fixture.container)
        XCTAssertTrue(originalAttachment.isCurrent)
        XCTAssertTrue(reset.completion?.isCurrent == true)
        XCTAssertTrue(nextBuild.finish(reset))
    }

    func testFocusExitClosingProviderStopsCheckedAdoptionBeforeCopyingCaretMarker() async throws {
        let retained = row("same slot")
        retained.text = "old label"
        retained.isFocusable = true
        let source = row("same slot")
        source.text = "already adopted text"
        source.isTextInputCaret = true
        source.isHitTestVisible = false
        let fixture = try MergedRuntimeFixture(
            previous: [retained], incoming: [source], beforeAdmission: { $0.requestFocus(retained) })
        defer { fixture.finish() }
        XCTAssertTrue(fixture.runtime.focusedNode === retained)
        XCTAssertFalse(retained.isTextInputCaret)
        var oldExits = 0
        var incomingExits = 0
        var updates = 0
        retained.onFocusExit = {
            oldExits += 1
            fixture.provider.close()
        }
        source.onFocusExit = { incomingExits += 1 }
        source.onUpdatePlatformView = { _ in updates += 1 }

        let result = fixture.initialBuild.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertNil(result.completion)
        XCTAssertFalse(fixture.initialBuild.admission.isCurrent)
        XCTAssertNil(fixture.provider.metadata)
        XCTAssertEqual(oldExits, 1)
        XCTAssertEqual(incomingExits, 0)
        XCTAssertEqual(updates, 0)
        // Completed writes are not rolled back, but the next property cannot
        // borrow the revoked admission after isFocusable's synchronous exit.
        XCTAssertEqual(retained.text, "already adopted text")
        XCTAssertFalse(retained.isFocusable)
        XCTAssertFalse(retained.isFocused)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertFalse(retained.isTextInputCaret)
        XCTAssertTrue(retained.isHitTestVisible)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === retained)
        XCTAssertTrue(retained.parent === fixture.container)
        XCTAssertFalse(fixture.initialBuild.finish(result))
    }

    private func row(_ tag: String, y: Double = 0) -> ViewNode {
        let node = ViewNode(frame: Rect(x: 0, y: y, width: 100, height: 20))
        node.nodeTag = tag
        return node
    }
}

@MainActor
private final class MergedRuntimeFixture {
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let container: ViewNode
    let runtime: RetainedViewRuntime
    let initialBuild: MergedRuntimeBuild
    private let lease: MergedRuntimeLease
    private var builds: [MergedRuntimeBuild]
    private var fixtureRoots: [ViewNode]
    private var didFinish = false

    init(
        previous: [ViewNode], incoming: [ViewNode], outside: [ViewNode] = [],
        beforeAdmission: @MainActor (RetainedViewRuntime) throws -> Void = { _ in }
    ) throws {
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        try Self.configure(provider, incoming: incoming, identityNodes: previous + incoming)
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 160, height: 80))
        container.isHitTestVisible = false
        for node in previous { container.addChild(node) }
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 240, height: 180))
        root.isHitTestVisible = false
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 0 }
        root.addChild(container)
        for node in outside { root.addChild(node) }
        // Initial layout, appearance, and ordinary pointer/focus setup precede
        // adapter installation and the admission's captured layout pass.
        _ = runtime.renderScene()
        try beforeAdmission(runtime)
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 80, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let lease = MergedRuntimeLease()
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        guard adapter.ownsAttachment(container) else { throw MergedRuntimeFixtureError.setup }
        let initialBuild = try MergedRuntimeBuild(adapter: adapter, container: container, runtime: runtime)
        self.provider = provider
        self.adapter = adapter
        self.container = container
        self.runtime = runtime
        self.lease = lease
        self.initialBuild = initialBuild
        self.builds = [initialBuild]
        self.fixtureRoots = previous + incoming + outside + [root, container]
    }

    func prepareNext(incoming: [ViewNode]) throws -> MergedRuntimeBuild {
        guard !didFinish, builds.allSatisfy(\.isFinished) else { throw MergedRuntimeFixtureError.setup }
        try Self.configure(provider, incoming: incoming, identityNodes: incoming)
        fixtureRoots.append(contentsOf: incoming)
        let build = try MergedRuntimeBuild(adapter: adapter, container: container, runtime: runtime)
        builds.append(build)
        return build
    }

    private static func configure(
        _ provider: RetainedLazyListDataSource<Int, [ViewNode]>, incoming: [ViewNode], identityNodes: [ViewNode]
    ) throws {
        guard
            provider.replaceData(
                [0], id: \.self, identityRoot: .init(segments: [.role(.content)]), rowContent: { _, _ in incoming })
        else { throw MergedRuntimeFixtureError.setup }
        let row = try XCTUnwrap(provider.metadata?.rows.first)
        let request = try XCTUnwrap(provider.request(for: row.token))
        let prefix = try XCTUnwrap(provider.identityPrefix(for: request))
        var configured: Set<ObjectIdentifier> = []
        for node in identityNodes where configured.insert(ObjectIdentifier(node)).inserted {
            let tag = try XCTUnwrap(node.nodeTag)
            node.retainedViewIdentity = prefix.appending(contentsOf: [.role(.content), .explicit(.init(tag))])
        }
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        runtime.stopRenderLifecycleCallbacks()
        provider.close()
        runtime.clock = { 0 }
        runtime.onAccessibilityFocusChanged = nil
        var pending = fixtureRoots
        var visited: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            pending.append(contentsOf: node.children)
            node.onFocusEnter = nil
            node.onFocusExit = nil
            node.onPointerDown = nil
            node.onPointerExit = nil
            node.onPointerUpOutside = nil
            node.onActivate = nil
            node.onUpdatePlatformView = nil
            if let editor = node.textInputController as? MergedRuntimeTextController { editor.onWillDetach = nil }
        }
        for build in builds where !build.isFinished { _ = build.finish() }
        runtime.cancelRenderLifecycleTasks()
    }
}

@MainActor
private final class MergedRuntimeBuild {
    let candidate: RetainedLazyListRuntimeAdapter.Candidate
    let admission: RetainedLazyListAdoptionAdmission
    private let adapter: RetainedLazyListRuntimeAdapter
    private let container: ViewNode
    private let runtime: RetainedViewRuntime
    private let epoch: MergedRuntimeEpoch
    private(set) var isFinished = false

    init(adapter: RetainedLazyListRuntimeAdapter, container: ViewNode, runtime: RetainedViewRuntime) throws {
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: 160, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 80))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let epoch = MergedRuntimeEpoch()
        coordinator.install(epoch, startedAt: sequence)
        var prepared = false
        defer {
            if !prepared {
                epoch.abandon()
                epoch.finishAfterCallbacks()
                coordinator.finishBuild()
            }
        }
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: container, runtime: runtime,
            coordinator: coordinator, sequence: sequence)
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget, admission: admission),
            admission.installCandidate(candidate), epoch.willAdopt(), admission.isCurrent
        else { throw MergedRuntimeFixtureError.setup }
        self.adapter = adapter
        self.container = container
        self.runtime = runtime
        self.epoch = epoch
        self.candidate = candidate
        self.admission = admission
        prepared = true
    }

    func replace() -> RetainedLazyListAdoptionResult {
        container.setChildren(candidate.children, admission: admission)
    }

    func reconcile() -> RetainedLazyListAdoptionResult {
        ComponentHost.reconcileChildren(
            of: container, oldChildren: container.children, newNodes: candidate.children, admission: admission)
    }

    @discardableResult
    func finish(_ result: RetainedLazyListAdoptionResult? = nil) -> Bool {
        guard !isFinished else { return false }
        let completed =
            result?.completed == true && admission.isCurrent
            && adapter.complete(candidate: candidate, adoptedChildren: container.children)
        isFinished = true
        if completed || admission.didMutate { epoch.commit() } else { epoch.abandon() }
        epoch.finishAfterCallbacks()
        runtime.retainedBuildCoordinator.finishBuild()
        return completed
    }
}

private enum MergedRuntimeFixtureError: Error { case setup }

@MainActor
private final class MergedRuntimeLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { MergedRuntimeEpoch() }
}

@MainActor
private final class MergedRuntimeEpoch: RetainedBuildEpoch {
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

/// Revocation is callback-free; willDetach is the first authored cleanup.
@MainActor
private final class MergedRuntimeTextController: RetainedTextInputController {
    var onWillDetach: (() -> Void)?
    private weak var owner: ViewNode?
    private var authorized = false
    private(set) var revokeCalls = 0
    private(set) var willDetachCalls = 0
    private(set) var detachCalls = 0

    func isAuthorized(for node: ViewNode) -> Bool { owner === node && authorized }
    func attach(to node: ViewNode) {
        owner = node
        authorized = true
    }
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func revokeOwnership(from node: ViewNode) {
        guard owner === node, authorized else { return }
        authorized = false
        revokeCalls += 1
    }
    func willDetach(from node: ViewNode) {
        guard owner === node else { return }
        willDetachCalls += 1
        onWillDetach?()
    }
    func detach(from node: ViewNode) {
        guard owner === node else { return }
        owner = nil
        authorized = false
        detachCalls += 1
    }
}

private final class MergedRuntimePresentationOwner {}

@MainActor
private final class MergedRuntimeReleaseObserver {
    weak var payload: MergedRuntimeReleasePayload?
}

private final class MergedRuntimeReleasePayload {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    deinit { MainActor.assumeIsolated { [action] in action() } }
}
