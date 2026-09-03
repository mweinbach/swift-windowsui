import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Frozen before the child-scope correction. These use the real reconciler,
/// candidate admission, and native frame declarations without changing budgets.
@MainActor
final class FrameAccessibilityChildScopeTests: XCTestCase {
    func testMatchedRowKeepsUntouchedContainerAvailableToOriginalAdmission() async throws {
        let fixture = try FrameChildScopeCheckedFixture()
        defer { fixture.close() }
        let containerRequest = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: fixture.outer))
        let rowRequest = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: fixture.retained))
        var updates = 0
        fixture.incoming.onUpdatePlatformView = { [weak fixture] node in
            guard let fixture else { return XCTFail("The original fixture must remain alive") }
            updates += 1
            XCTAssertTrue(node === fixture.retained)
            XCTAssertTrue(fixture.admission.isCurrent)
            XCTAssertTrue(containerRequest.isCurrent(in: fixture.runtime))
            XCTAssertTrue(fixture.runtime.permitsConservativeAccessibilityValueTarget(fixture.container))
            XCTAssertNil(fixture.runtime.accessibilitySemanticRequest(for: fixture.retained))
            XCTAssertFalse(rowRequest.isCurrent(in: fixture.runtime))
        }

        let result = ComponentHost.reconcileChildren(
            of: fixture.container, oldChildren: fixture.container.children,
            newNodes: fixture.candidate.children, admission: fixture.admission)

        XCTAssertEqual(updates, 1)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(fixture.container.children.first === fixture.retained)
        XCTAssertTrue(fixture.retained.children.first === fixture.leaf)
        let accepted = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: fixture.retained))
        XCTAssertTrue(accepted.semanticNode === fixture.leaf)
        XCTAssertEqual(accepted.metadata.label, "Incoming row")
        XCTAssertEqual(
            try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: fixture.outer)).metadata.label,
            "Untouched container")
    }

    func testMatchedRowCallbackCannotPublishAfterOriginalAdmissionCloses() async throws {
        let fixture = try FrameChildScopeCheckedFixture()
        defer { fixture.close() }
        let containerRequest = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: fixture.outer))
        let rowRequest = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: fixture.retained))
        var updates = 0
        fixture.incoming.onUpdatePlatformView = { [weak fixture] node in
            guard let fixture else { return XCTFail("The original fixture must remain alive") }
            updates += 1
            XCTAssertTrue(node === fixture.retained)
            XCTAssertTrue(fixture.admission.isCurrent)
            XCTAssertTrue(containerRequest.isCurrent(in: fixture.runtime))
            XCTAssertTrue(fixture.runtime.permitsConservativeAccessibilityValueTarget(fixture.container))
            XCTAssertNil(fixture.runtime.accessibilitySemanticRequest(for: fixture.retained))
            fixture.provider.close()
            XCTAssertFalse(fixture.admission.isCurrent)
        }

        let result = ComponentHost.reconcileChildren(
            of: fixture.container, oldChildren: fixture.container.children,
            newNodes: fixture.candidate.children, admission: fixture.admission)

        XCTAssertEqual(updates, 1)
        XCTAssertFalse(result.completed)
        XCTAssertNil(result.completion)
        XCTAssertTrue(fixture.container.children.first === fixture.retained)
        XCTAssertTrue(fixture.retained.children.first === fixture.leaf)
        XCTAssertFalse(rowRequest.isCurrent(in: fixture.runtime))
        for _ in 0..<3 {
            XCTAssertNil(fixture.runtime.accessibilitySemanticRequest(for: fixture.retained))
            XCTAssertNil(fixture.runtime.accessibilitySemanticRequest(for: fixture.leaf))
        }
        XCTAssertEqual(updates, 1)
    }

    func testFirstInsertedFramePublishesFromAcceptedParentWithoutOldRoots() async throws {
        try assertFreshRowPublication(replacingExisting: false)
    }

    func testEntirelyReplacedFramePublishesFromAcceptedParentInsteadOfDepartedRoot() async throws {
        try assertFreshRowPublication(replacingExisting: true)
    }

    func testDirectLeafUpdateStillSuspendsItsOriginalFrameAcrossSelectedBoundary() async throws {
        let leaf = frameChildScopeLeaf(label: "Original leaf")
        let selected = ViewNode.selectedContentBoundary(role: .viewThatFits, child: leaf)
        let outer = frameChildScopeFrame(content: selected, label: "Selected owner")
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120), children: [outer]))
        defer { frameChildScopeClose(runtime) }
        _ = runtime.renderFrame()
        let original = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: outer))
        let originalPath = try XCTUnwrap(selected.captureSelectedContentPath(in: runtime))
        XCTAssertTrue(originalPath.isInstalled(in: runtime))
        XCTAssertTrue(original.semanticNode === leaf)
        let incoming = frameChildScopeLeaf(label: "Incoming leaf")
        var updates = 0
        incoming.onUpdatePlatformView = { node in
            updates += 1
            XCTAssertTrue(node === leaf)
            XCTAssertNil(runtime.accessibilitySemanticRequest(for: outer))
            XCTAssertNil(runtime.accessibilitySemanticRequest(for: leaf))
            XCTAssertFalse(original.isCurrent(in: runtime))
        }

        let result = ComponentHost.adopt(source: incoming, into: leaf)

        XCTAssertEqual(updates, 1)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(selected.children.first === leaf)
        XCTAssertTrue(outer.children.first === selected)
        let accepted = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: outer))
        XCTAssertTrue(accepted.semanticNode === leaf)
        XCTAssertEqual(accepted.metadata.label, "Selected owner")
        XCTAssertEqual(leaf.accessibilityLabel, "Incoming leaf")
        XCTAssertFalse(original.isCurrent(in: runtime))
    }

    private func assertFreshRowPublication(replacingExisting: Bool) throws {
        let previousLeaf = frameChildScopeLeaf(label: "Previous leaf")
        let previous = frameChildScopeFrame(content: previousLeaf, label: "Previous row")
        previous.nodeTag = "previous-row"
        let container = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 120),
            children: replacingExisting ? [previous] : [])
        let outer = frameChildScopeFrame(content: container, label: "Untouched container")
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120), children: [outer]))
        defer { frameChildScopeClose(runtime) }
        _ = runtime.renderFrame()
        let outerElement = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: outer)).element
        let previousRequest = replacingExisting ? runtime.accessibilitySemanticRequest(for: previous) : nil
        if replacingExisting { XCTAssertNotNil(previousRequest) }
        let leaf = frameChildScopeLeaf(label: "Fresh leaf")
        let incoming = frameChildScopeFrame(content: leaf, label: "Fresh row")
        incoming.nodeTag = "fresh-row"
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: incoming))
        XCTAssertNil(runtime.accessibilitySemanticRequest(for: leaf))

        let result = ComponentHost.reconcileChildren(
            of: container, oldChildren: container.children, newNodes: [incoming])

        XCTAssertTrue(result.completed)
        XCTAssertNotNil(result.completion)
        XCTAssertEqual(container.children.count, 1)
        XCTAssertTrue(container.children.first === incoming)
        XCTAssertTrue(incoming.parent === container)
        XCTAssertTrue(incoming.children.first === leaf)
        let accepted = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: incoming))
        XCTAssertTrue(accepted.semanticNode === leaf)
        XCTAssertEqual(accepted.metadata.label, "Fresh row")
        XCTAssertTrue(accepted.isCurrent(in: runtime))
        let outerRequest = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: outer))
        XCTAssertTrue(outerRequest.element === outerElement)
        XCTAssertTrue(outerRequest.semanticNode === container)
        XCTAssertEqual(outerRequest.metadata.label, "Untouched container")
        if replacingExisting {
            XCTAssertNil(previous.parent)
            XCTAssertFalse(try XCTUnwrap(previousRequest).isCurrent(in: runtime))
        }
    }
}

@MainActor
private func frameChildScopeLeaf(label: String) -> ViewNode {
    let node = ViewNode(frame: Rect(x: 0, y: 0, width: 160, height: 24))
    node.accessibilityTraits = .isImage
    node.accessibilityLabel = label
    return node
}

@MainActor
private func frameChildScopeFrame(content: ViewNode, label: String) -> ViewNode {
    let frame = ViewNode(frame: Rect(x: 0, y: 0, width: 180, height: 32), children: [content])
    frame.declareAccessibilityFrameContent(content)
    frame.accessibilityLabel = label
    return frame
}

@MainActor
private func frameChildScopeClose(_ runtime: RetainedViewRuntime) {
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    runtime.root.removeAllChildren()
}

/// Real standalone candidate admission, not a permissive fake epoch. The outer
/// frame ends at the ordinary container; only its framed row is being copied.
@MainActor
private final class FrameChildScopeCheckedFixture {
    let runtime: RetainedViewRuntime
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let outer: ViewNode
    let container: ViewNode
    let retained: ViewNode
    let leaf: ViewNode
    let incoming: ViewNode
    let candidate: RetainedLazyListRuntimeAdapter.Candidate
    let admission: RetainedLazyListAdoptionAdmission
    let epoch: any RetainedBuildEpoch
    private var buildFinished = false

    init() throws {
        let leaf = frameChildScopeLeaf(label: "Retained leaf")
        let retained = frameChildScopeFrame(content: leaf, label: "Original row")
        let incoming = frameChildScopeFrame(
            content: frameChildScopeLeaf(label: "Incoming leaf"), label: "Incoming row")
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            provider.replaceData(
                [0], id: \.self, identityRoot: .init(segments: [.role(.content)]),
                rowContent: { _, _ in [incoming] }))
        let row = try XCTUnwrap(provider.metadata?.rows.first)
        let request = try XCTUnwrap(provider.request(for: row.token))
        let prefix = try XCTUnwrap(provider.identityPrefix(for: request))
        for node in [retained, incoming] {
            node.retainedViewIdentity = prefix.appending(contentsOf: [.role(.content)])
        }
        let container = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 120), children: [retained])
        let outer = frameChildScopeFrame(content: container, label: "Untouched container")
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120), children: [outer]))
        _ = runtime.renderFrame()
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 32, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let lease = try XCTUnwrap(adapter.installStandaloneBuildLease(in: runtime))
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        XCTAssertTrue(lease.canBuild)
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let epoch = try XCTUnwrap(lease.beginBuild())
        coordinator.install(epoch, startedAt: sequence)
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: container, runtime: runtime, coordinator: coordinator, sequence: sequence)
        var setupCompleted = false
        defer {
            if !setupCompleted {
                provider.close()
                epoch.abandon()
                epoch.finishAfterCallbacks()
                coordinator.finishBuild()
                frameChildScopeClose(runtime)
            }
        }
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: 200, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 120))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 128, roundLimit: 4))
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget, admission: admission),
            admission.installCandidate(candidate), epoch.willAdopt(), admission.isCurrent
        else { throw FrameChildScopeFixtureError.setup }
        self.runtime = runtime
        self.provider = provider
        self.adapter = adapter
        self.outer = outer
        self.container = container
        self.retained = retained
        self.leaf = leaf
        self.incoming = incoming
        self.candidate = candidate
        self.admission = admission
        self.epoch = epoch
        setupCompleted = true
    }

    func finishBuild() {
        guard !buildFinished else { return }
        buildFinished = true
        if admission.didMutate { epoch.commit() } else { epoch.abandon() }
        epoch.finishAfterCallbacks()
        runtime.retainedBuildCoordinator.finishBuild()
    }

    func close() {
        incoming.onUpdatePlatformView = nil
        retained.onUpdatePlatformView = nil
        admission.revoke()
        finishBuild()
        provider.close()
        frameChildScopeClose(runtime)
    }
}

private enum FrameChildScopeFixtureError: Error { case setup }
