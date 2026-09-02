import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

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
        var admissionWasCurrentAfterSeal = false
        fixture.events.onRelease = { [weak journal = fixture.journal, weak admission = fixture.admission] in
            _ = journal?.seal()
            admissionWasCurrentAfterSeal = admission?.isCurrent == true
        }

        let result = fixture.reconcile()

        XCTAssertEqual(fixture.events.releases, 1)
        XCTAssertTrue(admissionWasCurrentAfterSeal)
        XCTAssertFalse(fixture.admission.isCurrent)
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
    private let stateCoordinator: StateMountCoordinator
    private let activity: any RetainedLazyListBuildActivity
    private let descriptorScope: RetainedLazyListDescriptorBuildScope
    private let descriptorSource: ViewNode

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100)))
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60))
        let stateCoordinator = StateMountCoordinator(
            invalidate: {}, observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        let build = try XCTUnwrap(stateCoordinator.beginBuild())
        var setupCompleted = false
        defer {
            if !setupCompleted {
                build.abandon()
                build.finishAfterCallbacks()
                stateCoordinator.close()
            }
        }
        let activity = try XCTUnwrap(build as? any RetainedLazyListBuildActivity)
        let descriptorScope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: container.lazyListActivityStorage().descriptorOwnerLifetime)
        defer { if !setupCompleted { descriptorScope.finish() } }
        guard activity.bindLazyListDescriptorScope(descriptorScope) else {
            throw ButtonFinalAdmissionError.activityScopeBinding
        }
        var buildContext = ViewBuildContext(
            stateMountCoordinator: stateCoordinator, canvasSizeProvider: { Size(width: 200, height: 100) },
            invalidateHandler: {}
        ).withViewIdentityType(ButtonFinalAdmissionRoot.self)
        _ = try XCTUnwrap(stateCoordinator.install(ButtonFinalAdmissionRoot(), context: &buildContext))
        let descriptorReceipt = try XCTUnwrap(stateCoordinator.descriptorResolutionReceipt(in: buildContext))
        let descriptorIdentity = buildContext.retainedViewIdentity.appending(.role(.content))
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
                [0], id: \.self, identityRoot: descriptorIdentity, descriptorBuildScope: descriptorScope,
                rowContent: { _, _ in [incoming, sourceNested] }))
        let metadata = try XCTUnwrap(provider.metadata)
        let proposal = try XCTUnwrap(
            stateCoordinator.stageLazyMembership(
                at: descriptorIdentity, metadata: metadata, context: buildContext, receipt: descriptorReceipt))
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
        let binding = proposal.nativeBinding
        guard adapter.installManagedLogicalDescriptor(binding) else {
            throw ButtonFinalAdmissionError.descriptorInstallation
        }
        let descriptorSource = ViewNode()
        descriptorSource.retainedLazyListAdapter = adapter
        container.addChild(retained)
        container.addChild(previousNested)
        runtime.root.addChild(container)
        let lease = ButtonFinalAdmissionLease()
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        coordinator.install(build, startedAt: sequence)
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: container, runtime: runtime, coordinator: coordinator, sequence: sequence)
        defer {
            if !setupCompleted {
                admission.revoke()
                coordinator.finishBuild()
            }
        }
        // A selected-row journal requires the same managed descriptor and real
        // build activity as Runtime. An unmanaged adapter refuses reconciliation
        // before copying any Button, so it cannot test final admission cleanup.
        let journal = RetainedLazyListAdoptionJournal(admission: admission, transaction: RetainedBuildTransaction())
        guard journal.bindDescriptorScope(descriptorScope) else {
            throw ButtonFinalAdmissionError.journalScopeBinding
        }
        guard journal.registerSourceDescriptor(binding, on: descriptorSource) != nil else {
            throw ButtonFinalAdmissionError.descriptorRegistration
        }
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 100, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 60))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget, admission: admission,
                activity: activity, journal: journal)
        else { throw ButtonFinalAdmissionError.noCandidate }
        guard admission.installCandidate(candidate) else {
            throw ButtonFinalAdmissionError.candidateInstallation
        }
        guard admission.isCurrent else {
            throw ButtonFinalAdmissionError.candidateCurrent
        }
        let preparation = try XCTUnwrap(journal.preparation())
        let prepared = try XCTUnwrap(activity.willAdoptLazyList(preparation))
        guard journal.beginAdoption(preparation, preparedActivity: prepared) else {
            throw ButtonFinalAdmissionError.journalAdoption
        }
        guard candidate.configureManagedPublication(preparation) else {
            throw ButtonFinalAdmissionError.candidatePublication
        }
        guard journal.markMutationStarted() else {
            throw ButtonFinalAdmissionError.mutationStart
        }
        guard case .ready(let publication) = journal.prepareDescriptorCopy(from: descriptorSource, to: container) else {
            throw ButtonFinalAdmissionError.descriptorCopyPreparation
        }
        guard journal.recordAcceptedLogicalDeclaration(publication) != nil else {
            throw ButtonFinalAdmissionError.descriptorPublication
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
        self.stateCoordinator = stateCoordinator
        self.activity = activity
        self.descriptorScope = descriptorScope
        self.descriptorSource = descriptorSource
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
        let disposition = journal.seal()
        journal.finishAcceptedTaskCleanup()
        journal.releaseUnadoptedTransport()
        candidate.discardBuiltContent()
        activity.commitLazyList(disposition)
        activity.finishAfterCallbacks()
        descriptorScope.finish()
        coordinator.finishBuild()
        stateCoordinator.close()
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

private struct ButtonFinalAdmissionRoot {}

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
    case activityScopeBinding
    case descriptorInstallation
    case journalScopeBinding
    case descriptorRegistration
    case candidateInstallation
    case candidateCurrent
    case journalAdoption
    case candidatePublication
    case mutationStart
    case descriptorCopyPreparation
    case descriptorPublication
}
