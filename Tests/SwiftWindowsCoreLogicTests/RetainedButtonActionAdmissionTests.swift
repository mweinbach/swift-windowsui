import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedButtonActionAdmissionTests: XCTestCase {
    func testRejectedSourceDestructorRevokesProviderBeforeNewButtonAcceptance() async throws {
        let fixture = try ButtonFinalAdmissionFixture()
        defer { fixture.finish() }
        fixture.events.onRelease = { [weak provider = fixture.provider] in provider?.close() }

        let result = fixture.reconcile()

        XCTAssertEqual(fixture.events.releases, 1)
        XCTAssertFalse(fixture.admission.isCurrent)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(fixture.retained.buttonActionOwner?.isRetired == true)
        fixture.candidate.discardBuiltContent()
        fixture.retained.onActivate?()
        fixture.savedIncoming?()
        XCTAssertEqual(fixture.events.activations, 0)
    }

    func testRejectedSourceDestructorSealsJournalBeforeNewButtonAcceptance() async throws {
        let fixture = try ButtonFinalAdmissionFixture()
        defer { fixture.finish() }
        fixture.events.onRelease = { [weak journal = fixture.journal] in _ = journal?.seal() }

        let result = fixture.reconcile()

        XCTAssertEqual(fixture.events.releases, 1)
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertFalse(fixture.journal.canContinueAdoption)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(fixture.retained.buttonActionOwner?.isRetired == true)
        fixture.candidate.discardBuiltContent()
        fixture.retained.onActivate?()
        fixture.savedIncoming?()
        XCTAssertEqual(fixture.events.activations, 0)
    }

    func testRejectedSourceCleanupAcceptsNewButtonWhenNativeProofsStayCurrent() async throws {
        let fixture = try ButtonFinalAdmissionFixture()
        defer { fixture.finish() }

        let result = fixture.reconcile()

        XCTAssertEqual(fixture.events.releases, 1)
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertTrue(fixture.journal.canContinueAdoption)
        XCTAssertTrue(result.completed)
        XCTAssertFalse(fixture.retained.buttonActionOwner?.isRetired == true)
        fixture.candidate.discardBuiltContent()
        fixture.retained.onActivate?()
        XCTAssertEqual(fixture.events.activations, 1)
    }
}

/// A selected row has a Button beside a preserved nested lazy container. The
/// unused Button under the source container belongs to the candidate, but is
/// deliberately not copied because the retained container keeps its children.
@MainActor
private final class ButtonFinalAdmissionFixture {
    let runtime: RetainedViewRuntime
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let container: ViewNode
    let retained: ViewNode
    let candidate: RetainedLazyListRuntimeAdapter.Candidate
    let admission: RetainedLazyListAdoptionAdmission
    let journal: RetainedLazyListAdoptionJournal
    let coordinator: RetainedBuildCoordinator
    let lease: ButtonFinalAdmissionLease
    let events: ButtonFinalAdmissionEvents
    let savedIncoming: (() -> Void)?

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100)))
        let events = ButtonFinalAdmissionEvents()
        let retained = Self.button(runtime: runtime) {}
        let incoming = Self.button(runtime: runtime) { events.activations += 1 }
        retained.nodeTag = "button"
        incoming.nodeTag = "button"
        let nestedProvider = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(nestedProvider.replaceData([], id: \.self) { _ in [] })
        let nestedAdapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: nestedProvider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 4, maximumProtectedRecords: 1))
        let previousNested = ViewNode()
        let sourceNested = ViewNode()
        previousNested.nodeTag = "nested"
        sourceNested.nodeTag = "nested"
        previousNested.retainedLazyListAdapter = nestedAdapter
        sourceNested.retainedLazyListAdapter = nestedAdapter
        let unused = Self.unusedButton(runtime: runtime, events: events)
        sourceNested.addChild(unused)

        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            provider.replaceData(
                [0], id: \.self, identityRoot: .init(segments: [.role(.content)]),
                rowContent: { _, _ in [incoming, sourceNested] }))
        let row = try XCTUnwrap(provider.metadata?.rows.first)
        let request = try XCTUnwrap(provider.request(for: row.token))
        let prefix = try XCTUnwrap(provider.identityPrefix(for: request))
        for node in [retained, incoming, previousNested, sourceNested] {
            node.retainedViewIdentity = prefix.appending(contentsOf: [.role(.content), .explicit(.init(node.nodeTag!))])
        }
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 8, maximumProtectedRecords: 1))
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60))
        container.addChild(retained)
        container.addChild(previousNested)
        runtime.root.addChild(container)
        let lease = ButtonFinalAdmissionLease()
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: container, runtime: runtime, coordinator: coordinator, sequence: sequence)
        var setupCompleted = false
        defer {
            if !setupCompleted {
                admission.revoke()
                coordinator.finishBuild()
            }
        }
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 100, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 60))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget, admission: admission)
        else { throw ButtonFinalAdmissionError.noCandidate }
        guard admission.installCandidate(candidate), admission.isCurrent else {
            throw ButtonFinalAdmissionError.noAdmission
        }
        let journal = RetainedLazyListAdoptionJournal(admission: admission, transaction: RetainedBuildTransaction())
        let preparation = try XCTUnwrap(journal.preparation())
        let activity = RetainedLazyListPreparedActivity(preparation: preparation, logicalMembershipPlans: [])
        guard journal.beginAdoption(preparation, preparedActivity: activity) else {
            throw ButtonFinalAdmissionError.noAdmission
        }
        self.runtime = runtime
        self.events = events
        self.provider = provider
        self.container = container
        self.retained = retained
        self.candidate = candidate
        self.admission = admission
        self.journal = journal
        self.coordinator = coordinator
        self.lease = lease
        savedIncoming = incoming.onActivate
        setupCompleted = true
    }

    func reconcile() -> RetainedLazyListAdoptionResult {
        ComponentHost.reconcileChildren(
            of: container, oldChildren: container.children, newNodes: candidate.children,
            admission: admission, lazyJournal: journal)
    }

    func finish() {
        events.onRelease = nil
        admission.revoke()
        _ = journal.seal()
        journal.finishAcceptedTaskCleanup()
        journal.releaseUnadoptedTransport()
        candidate.discardBuiltContent()
        coordinator.finishBuild()
        provider.close()
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
    }

    private static func button(runtime: RetainedViewRuntime, action: @escaping () -> Void) -> ViewNode {
        Controls.button(
            runtime: runtime, frame: Rect(x: 0, y: 0, width: 80, height: 20), cornerRadius: 4,
            palette: SurfacePalette(idle: .gray, focused: .blue, pressed: .black), action: action)
    }

    @inline(never)
    private static func unusedButton(runtime: RetainedViewRuntime, events: ButtonFinalAdmissionEvents) -> ViewNode {
        let probe = ButtonFinalAdmissionReleaseProbe(events)
        return button(runtime: runtime) { [probe] in withExtendedLifetime(probe) {} }
    }
}

@MainActor
private final class ButtonFinalAdmissionEvents {
    var activations = 0
    var releases = 0
    var onRelease: (@MainActor () -> Void)?
}

@MainActor
private final class ButtonFinalAdmissionReleaseProbe {
    let events: ButtonFinalAdmissionEvents
    init(_ events: ButtonFinalAdmissionEvents) { self.events = events }
    isolated deinit {
        events.releases += 1
        events.onRelease?()
    }
}

@MainActor
private final class ButtonFinalAdmissionLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { nil }
}

private enum ButtonFinalAdmissionError: Error {
    case noCandidate
    case noAdmission
}
