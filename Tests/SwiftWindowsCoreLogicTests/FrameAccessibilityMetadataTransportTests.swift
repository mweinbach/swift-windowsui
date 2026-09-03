import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Frozen before private production implementation. This captures copied
/// accepted metadata only; capture never performs layout or authorizes effects.
@MainActor
final class FrameAccessibilityMetadataTransportTests: XCTestCase {
    func testDirectAdoptionCopiesAndClearsAllExplicitOverrides() async throws {
        try assertCopiesAndClears(route: .direct)
    }

    func testMatchedChildAdoptionCopiesAndClearsAllExplicitOverrides() async throws {
        try assertCopiesAndClears(route: .matchedChild)
    }

    func testTraitEditsRetainInnerToOuterOrderInsteadOfWrapperFinalBits() async throws {
        for route in FrameMetadataRoute.allCases {
            let fixture = try FrameMetadataFixture(route: route)
            defer { fixture.close() }
            let initial = try XCTUnwrap(fixture.request())
            XCTAssertEqual(initial.metadata.traits, .isImage, route.rawValue)
            XCTAssertEqual(fixture.leaf.accessibilityTraits, [.isButton, .isImage])
            XCTAssertTrue(try fixture.adopt(stage: 1).completed)
            XCTAssertEqual(try XCTUnwrap(fixture.request()).metadata.traits, [.isButton, .isHeader])
            XCTAssertTrue(try fixture.adopt(stage: 2).completed)
            XCTAssertEqual(try XCTUnwrap(fixture.request()).metadata.traits, [.isButton, .isImage])
            XCTAssertTrue(try fixture.adopt(stage: 0).completed)
            XCTAssertEqual(try XCTUnwrap(fixture.request()).metadata.traits, .isImage)
            XCTAssertFalse(
                initial.isCurrent(in: fixture.runtime), "A later equal value does not revive an old operation")
        }
    }

    func testDirectMetadataPublicationIsSuspendedDuringPayloadRelease() async throws {
        try assertReentrantPublication(route: .direct, interrupt: false)
    }

    func testMatchedChildMetadataPublicationIsSuspendedDuringPayloadRelease() async throws {
        try assertReentrantPublication(route: .matchedChild, interrupt: false)
    }

    func testDirectInterruptedAdoptionCannotPublishOrReconstructMetadata() async throws {
        try assertReentrantPublication(route: .direct, interrupt: true)
    }

    func testMatchedChildInterruptedAdoptionCannotPublishOrReconstructMetadata() async throws {
        try assertReentrantPublication(route: .matchedChild, interrupt: true)
    }

    func testBothPathsMapFreshDeclarationsOntoRetainedContentWithoutKeepingCandidates() async throws {
        for route in FrameMetadataRoute.allCases {
            let fixture = try FrameMetadataFixture(route: route)
            defer { fixture.close() }
            let frame = fixture.frame
            let leaf = fixture.leaf
            weak var discardedSourceLeaf: ViewNode?
            @inline(never)
            func adoptCandidate() throws {
                let candidate = fixture.makeCandidate(stage: 1)
                let sourceFrame = route == .direct ? candidate : try XCTUnwrap(candidate.children.first)
                let sourceInner = try XCTUnwrap(sourceFrame.children.first)
                discardedSourceLeaf = try XCTUnwrap(sourceInner.children.first)
                XCTAssertTrue(discardedSourceLeaf !== leaf)
                XCTAssertTrue(ComponentHost.adopt(source: candidate, into: fixture.root).completed)
                let request = try XCTUnwrap(fixture.request())
                XCTAssertTrue(request.semanticNode === leaf)
                XCTAssertTrue(request.semanticNode !== discardedSourceLeaf)
                XCTAssertTrue(fixture.frame === frame)
                XCTAssertTrue(try XCTUnwrap(frame.children.first).children.first === leaf)
            }
            try adoptCandidate()
            XCTAssertNil(discardedSourceLeaf, "The accepted declaration must not own its discarded source content")
            XCTAssertTrue(try XCTUnwrap(fixture.request()).semanticNode === leaf)
        }
    }

    func testPublishedMetadataCaptureDoesNotReadOrWriteAnEditorBinding() async throws {
        let probe = FrameMetadataBindingProbe()
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120)))
        defer { frameMetadataClose(runtime) }
        let frame = frameMetadataNode(
            TextField(
                "Field",
                text: Binding(
                    get: {
                        probe.reads += 1
                        return "Stored"
                    }, set: { _ in probe.writes += 1 })
            )
            .accessibilityDescription("base description").accessibilityLanguage("en")
            .frame(width: 160, height: 32).accessibilityDescription(nil).accessibilityLanguage(nil)
            .accessibilityValue("authored metadata"), in: runtime)
        runtime.root.addChild(frame)
        _ = runtime.renderFrame()
        let reads = probe.reads
        let first = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        let second = try XCTUnwrap(runtime.accessibilitySemanticRequest(for: frame))
        XCTAssertTrue(first.semanticNode === second.semanticNode)
        XCTAssertNil(first.metadata.description)
        XCTAssertNil(first.metadata.language)
        XCTAssertEqual(first.metadata.value, "authored metadata")
        XCTAssertTrue(first.isCurrent(in: runtime))
        XCTAssertEqual(probe.reads, reads)
        XCTAssertEqual(probe.writes, 0)
        XCTAssertNil(runtime.focusedNode)
    }

    func testCheckedDirectAdmissionCopiesAndClearsWithoutPrematurePublication() async throws {
        try assertCheckedTransport(useChildrenEntry: false)
    }

    func testCheckedChildAdmissionCopiesAndClearsWithoutPrematurePublication() async throws {
        try assertCheckedTransport(useChildrenEntry: true)
    }

    private func assertCheckedTransport(useChildrenEntry: Bool) throws {
        for (previousStage, incomingStage) in [(2, 0), (0, 1), (1, 2)] {
            for interrupts in [false, true] {
                let fixture = try FrameMetadataCheckedFixture(
                    previousStage: previousStage, incomingStage: incomingStage)
                defer { fixture.close() }
                let retained = fixture.retained
                let oldInner = try XCTUnwrap(retained.children.first)
                let oldLeaf = try XCTUnwrap(oldInner.children.first)
                let original = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: retained))
                var updates = 0
                var unavailable: [Bool] = []
                fixture.incoming.onUpdatePlatformView = { [weak fixture] node in
                    guard let fixture else { return }
                    updates += 1
                    XCTAssertTrue(node === retained)
                    XCTAssertTrue(retained.children.first === oldInner)
                    XCTAssertTrue(oldInner.children.first === oldLeaf)
                    unavailable.append(fixture.runtime.accessibilitySemanticRequest(for: retained) == nil)
                    XCTAssertFalse(original.isCurrent(in: fixture.runtime))
                    if interrupts { fixture.provider.close() }
                }
                let result =
                    useChildrenEntry
                    ? ComponentHost.reconcileChildren(
                        of: fixture.container, oldChildren: fixture.container.children,
                        newNodes: fixture.candidate.children, admission: fixture.admission)
                    : ComponentHost.adopt(source: fixture.incoming, into: retained, admission: fixture.admission)
                fixture.finishBuild()
                XCTAssertEqual(updates, 1)
                XCTAssertEqual(unavailable, [true])
                XCTAssertTrue(retained.children.first === oldInner)
                XCTAssertTrue(oldInner.children.first === oldLeaf)
                if interrupts {
                    XCTAssertFalse(result.completed)
                    XCTAssertNil(fixture.runtime.accessibilitySemanticRequest(for: retained))
                    XCTAssertNil(fixture.runtime.accessibilitySemanticRequest(for: oldLeaf))
                } else {
                    XCTAssertTrue(result.completed)
                    let accepted = try XCTUnwrap(fixture.runtime.accessibilitySemanticRequest(for: retained))
                    XCTAssertTrue(accepted.semanticNode === oldLeaf)
                    assertMetadata(accepted.metadata, stage: incomingStage)
                }
            }
        }
    }

    private func assertCopiesAndClears(route: FrameMetadataRoute) throws {
        let fixture = try FrameMetadataFixture(route: route)
        defer { fixture.close() }
        let frame = fixture.frame
        let inner = try XCTUnwrap(frame.children.first)
        let leaf = fixture.leaf
        let original = try XCTUnwrap(fixture.request())
        assertMetadata(original.metadata, stage: 0)
        XCTAssertTrue(original.semanticNode === leaf)
        XCTAssertTrue(original.isCurrent(in: fixture.runtime))
        // Copy inner values after removing outer explicit nil/false/zero/empty.
        XCTAssertTrue(try fixture.adopt(stage: 1).completed, route.rawValue)
        XCTAssertFalse(original.isCurrent(in: fixture.runtime))
        assertMetadata(try XCTUnwrap(fixture.request()).metadata, stage: 1)
        XCTAssertTrue(fixture.frame === frame)
        XCTAssertTrue(frame.children.first === inner)
        XCTAssertTrue(inner.children.first === leaf)
        // Clear the inner intent too; the untouched base must become effective.
        XCTAssertTrue(try fixture.adopt(stage: 2).completed, route.rawValue)
        assertMetadata(try XCTUnwrap(fixture.request()).metadata, stage: 2)
        XCTAssertTrue(fixture.frame === frame)
        XCTAssertTrue(frame.children.first === inner)
        XCTAssertTrue(inner.children.first === leaf)
        XCTAssertEqual(leaf.accessibilityDescription, "base description")
        XCTAssertEqual(leaf.accessibilityLanguage, "en")
        XCTAssertEqual(leaf.accessibilitySortPriority, 7)
        XCTAssertEqual(leaf.accessibilityInputLabels, ["base input"])
        XCTAssertTrue(leaf.isAccessibilityHidden)
        XCTAssertEqual(leaf.accessibilityRespondsToUserInteraction, false)
        XCTAssertEqual(leaf.accessibilityLabel, "base label")
        XCTAssertEqual(leaf.accessibilityHint, "base hint")
        XCTAssertEqual(leaf.accessibilityValue, "base value")
        XCTAssertEqual(leaf.accessibilityTraits, [.isButton, .isImage])
    }

    private func assertMetadata(_ metadata: RetainedAccessibilitySemanticMetadata, stage: Int) {
        switch stage {
        case 0:
            XCTAssertNil(metadata.description)
            XCTAssertNil(metadata.language)
            XCTAssertEqual(metadata.respondsToUserInteraction, false)
            XCTAssertFalse(metadata.isHidden)
            XCTAssertEqual(metadata.sortPriority, 0)
            XCTAssertEqual(metadata.inputLabels, [])
            XCTAssertEqual(metadata.label, "")
            XCTAssertEqual(metadata.hint, "")
            XCTAssertEqual(metadata.value, "")
            XCTAssertEqual(metadata.traits, .isImage)
        case 1:
            XCTAssertEqual(metadata.description, "inner description")
            XCTAssertEqual(metadata.language, "fr")
            XCTAssertEqual(metadata.respondsToUserInteraction, true)
            XCTAssertFalse(metadata.isHidden)
            XCTAssertEqual(metadata.sortPriority, 3)
            XCTAssertEqual(metadata.inputLabels, ["inner input"])
            XCTAssertEqual(metadata.label, "inner label")
            XCTAssertEqual(metadata.hint, "inner hint")
            XCTAssertEqual(metadata.value, "inner value")
            XCTAssertEqual(metadata.traits, [.isButton, .isHeader])
        default:
            XCTAssertEqual(metadata.description, "base description")
            XCTAssertEqual(metadata.language, "en")
            XCTAssertEqual(metadata.respondsToUserInteraction, false)
            XCTAssertTrue(metadata.isHidden)
            XCTAssertEqual(metadata.sortPriority, 7)
            XCTAssertEqual(metadata.inputLabels, ["base input"])
            XCTAssertEqual(metadata.label, "base label")
            XCTAssertEqual(metadata.hint, "base hint")
            XCTAssertEqual(metadata.value, "base value")
            XCTAssertEqual(metadata.traits, [.isButton, .isImage])
        }
        XCTAssertEqual(metadata.identifier, "metadata-subject")
    }

    private func assertReentrantPublication(route: FrameMetadataRoute, interrupt: Bool) throws {
        let reentry = FrameMetadataReentry()
        let fixture = try FrameMetadataFixture(route: route, onRelease: { reentry.run(interrupt: interrupt) })
        defer { fixture.close() }
        reentry.runtime = fixture.runtime
        reentry.frame = fixture.frame
        reentry.leaf = fixture.leaf
        reentry.original = try XCTUnwrap(fixture.request())
        let result = try fixture.adopt(stage: 1)
        XCTAssertEqual(reentry.calls, 1, route.rawValue)
        XCTAssertEqual(reentry.unavailableDuringRelease, [true])
        XCTAssertEqual(reentry.originalCurrentDuringRelease, [false])
        if interrupt {
            XCTAssertFalse(result.completed)
            XCTAssertNil(fixture.request())
            XCTAssertNil(fixture.runtime.accessibilitySemanticRequest(for: fixture.leaf))
            XCTAssertNil(fixture.request(), "A second read cannot reconstruct an unaccepted declaration")
            XCTAssertFalse(try XCTUnwrap(reentry.original).isCurrent(in: fixture.runtime))
        } else {
            XCTAssertTrue(result.completed)
            let accepted = try XCTUnwrap(fixture.request())
            XCTAssertTrue(accepted.semanticNode === fixture.leaf)
            assertMetadata(accepted.metadata, stage: 1)
        }
    }
}

private enum FrameMetadataRoute: String, CaseIterable {
    case direct
    case matchedChild
}

@MainActor
private final class FrameMetadataBindingProbe {
    var reads = 0
    var writes = 0
}

@MainActor
private final class FrameMetadataReentry {
    weak var runtime: RetainedViewRuntime?
    weak var frame: ViewNode?
    weak var leaf: ViewNode?
    var original: RetainedAccessibilitySemanticRequest?
    var calls = 0
    var unavailableDuringRelease: [Bool] = []
    var originalCurrentDuringRelease: [Bool] = []

    func run(interrupt: Bool) {
        guard let runtime, let frame, let leaf else { return }
        calls += 1
        unavailableDuringRelease.append(runtime.accessibilitySemanticRequest(for: frame) == nil)
        originalCurrentDuringRelease.append(original?.isCurrent(in: runtime) == true)
        if interrupt, let inner = leaf.parent {
            inner.removeAllChildren()
            inner.addChild(leaf)
        }
    }
}

@MainActor
private final class FrameMetadataRetirement {
    let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    deinit { MainActor.assumeIsolated { onRelease() } }
}

@MainActor
private final class FrameMetadataFixture {
    let runtime: RetainedViewRuntime
    let root: ViewNode
    let frame: ViewNode
    let leaf: ViewNode
    let route: FrameMetadataRoute

    init(route: FrameMetadataRoute, onRelease: (@MainActor () -> Void)? = nil) throws {
        self.route = route
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120)))
        self.runtime = runtime
        let frame = frameMetadataBuild(stage: 0, in: runtime, onRelease: onRelease)
        self.frame = frame
        self.leaf = try XCTUnwrap(try XCTUnwrap(frame.children.first).children.first)
        let root = route == .direct ? frame : ViewNode(children: [frame])
        self.root = root
        runtime.root.addChild(root)
        _ = runtime.renderFrame()
    }

    func request() -> RetainedAccessibilitySemanticRequest? { runtime.accessibilitySemanticRequest(for: frame) }

    func makeCandidate(stage: Int) -> ViewNode {
        let frame = frameMetadataBuild(stage: stage, in: runtime, onRelease: nil)
        return route == .direct ? frame : ViewNode(children: [frame])
    }

    @inline(never)
    func adopt(stage: Int) throws -> RetainedLazyListAdoptionResult {
        let source = makeCandidate(stage: stage)
        return ComponentHost.adopt(source: source, into: root)
    }

    func close() { frameMetadataClose(runtime) }
}

@MainActor
private func frameMetadataBuild(
    stage: Int, in runtime: RetainedViewRuntime,
    onRelease: (@MainActor () -> Void)?
) -> ViewNode {
    let base = Button("Control") {}.accessibilityDescription("base description").accessibilityLanguage("en")
        .accessibilityRespondsToUserInteraction(false).accessibilityHidden(true).accessibilitySortPriority(7)
        .accessibilityInputLabels(["base input"]).accessibilityLabel("base label").accessibilityHint("base hint")
        .accessibilityValue("base value").accessibilityAddTraits(.isImage).frame(width: 100, height: 40)
    let inner: AnyView
    if stage < 2 {
        inner = AnyView(
            base.accessibilityDescription("inner description").accessibilityLanguage("fr")
                .accessibilityRespondsToUserInteraction(true).accessibilityHidden(false).accessibilitySortPriority(3)
                .accessibilityInputLabels(["inner input"]).accessibilityLabel("inner label").accessibilityHint(
                    "inner hint"
                )
                .accessibilityValue("inner value").accessibilityRemoveTraits(.isImage).accessibilityAddTraits(.isHeader)
        )
    } else {
        inner = AnyView(
            base.opacity(1).opacity(1).opacity(1).opacity(1).opacity(1).opacity(1)
                .opacity(1).opacity(1).opacity(1).opacity(1).opacity(1))
    }
    let outerBase = inner.frame(width: 160, height: 80)
    let outer: AnyView
    if stage == 0 {
        outer = AnyView(
            outerBase.accessibilityDescription(nil).accessibilityLanguage(nil)
                .accessibilityRespondsToUserInteraction(false).accessibilityHidden(false).accessibilitySortPriority(0)
                .accessibilityInputLabels([]).accessibilityLabel("").accessibilityHint("").accessibilityValue("")
                .accessibilityRemoveTraits([.isButton, .isHeader]).accessibilityAddTraits(.isImage))
    } else {
        outer = AnyView(
            outerBase.opacity(1).opacity(1).opacity(1).opacity(1).opacity(1).opacity(1)
                .opacity(1).opacity(1).opacity(1).opacity(1).opacity(1))
    }
    let identified = outer.accessibilityIdentifier("metadata-subject")
    if let onRelease {
        let payload = FrameMetadataRetirement(onRelease)
        return frameMetadataNode(
            identified.accessibilityAction { [payload] in withExtendedLifetime(payload) {} },
            in: runtime)
    }
    return frameMetadataNode(identified.opacity(1), in: runtime)
}

@MainActor
private func frameMetadataNode<Content: View>(_ content: Content, in runtime: RetainedViewRuntime) -> ViewNode {
    let context = ViewBuildContext(canvasSizeProvider: { Size(width: 200, height: 120) }, invalidateHandler: {})
    return content.makeComponent(context: context).makeNode(runtime: runtime)
}

@MainActor
private func frameMetadataClose(_ runtime: RetainedViewRuntime) {
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    runtime.root.removeAllChildren()
}

/// Real candidate-backed admission using the production standalone lease/epoch.
/// Identity prefixes are assigned before attachment, exactly as native row setup;
/// no captured identity is refreshed and no permissive fake epoch is introduced.
@MainActor
private final class FrameMetadataCheckedFixture {
    let runtime: RetainedViewRuntime
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let container: ViewNode
    let retained: ViewNode
    let incoming: ViewNode
    let candidate: RetainedLazyListRuntimeAdapter.Candidate
    let admission: RetainedLazyListAdoptionAdmission
    let epoch: any RetainedBuildEpoch
    private var buildFinished = false

    init(previousStage: Int, incomingStage: Int) throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120)))
        let retained = frameMetadataBuild(stage: previousStage, in: runtime, onRelease: nil)
        let incoming = frameMetadataBuild(stage: incomingStage, in: runtime, onRelease: nil)
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            provider.replaceData(
                [0], id: \.self,
                identityRoot: .init(segments: [.role(.content)]), rowContent: { _, _ in [incoming] }))
        let row = try XCTUnwrap(provider.metadata?.rows.first)
        let request = try XCTUnwrap(provider.request(for: row.token))
        let prefix = try XCTUnwrap(provider.identityPrefix(for: request))
        for node in [retained, incoming] {
            let original = try XCTUnwrap(node.retainedViewIdentity)
            node.retainedViewIdentity = prefix.appending(contentsOf: [.role(.content)] + original.segments)
        }
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 80, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let lease = try XCTUnwrap(adapter.installStandaloneBuildLease(in: runtime))
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120), children: [retained])
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        runtime.root.addChild(container)
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
                frameMetadataClose(runtime)
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
        else { throw FrameMetadataFixtureError.setup }
        self.runtime = runtime
        self.provider = provider
        self.adapter = adapter
        self.container = container
        self.retained = retained
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
        frameMetadataClose(runtime)
    }
}

private enum FrameMetadataFixtureError: Error { case setup }
