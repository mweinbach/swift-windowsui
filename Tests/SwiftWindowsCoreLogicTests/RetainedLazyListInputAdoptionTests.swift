import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Source fixtures for the dormant checked adopter's active scroll-input
/// boundary. Geometry and initial capture come from the real retained input
/// path before admission. These do not qualify public List or native input.
@MainActor
final class RetainedLazyListInputAdoptionTests: XCTestCase {
    func testNestedActiveIndicatorDisableRejectsBeforeHoverOrContentMutation() async throws {
        let pair = InputAdoptionRowPair(incomingEnabled: false)
        let hover = InputAdoptionHoverProbe()
        var grab = Point(x: 0, y: 0)
        let fixture = try InputAdoptionFixture(
            previous: [pair.retained], incoming: [pair.source], outside: hover.nodes,
            beforeAdmission: { runtime, provider in
                try hover.prime(in: runtime, provider: provider)
                grab = try InputAdoptionFixture.grabIndicator(in: runtime, of: pair.oldScroll)
            })
        defer { fixture.finish() }
        let proofs = [pair.retained, pair.oldScroll, pair.oldContent].map { $0.captureLazyListAttachmentProof() }
        let dialog = pair.oldContent.beginFileDialogPresentation(kind: .importer)
        let offset = pair.oldScroll.scrollOffset
        var updates = 0
        pair.source.onUpdatePlatformView = { _ in updates += 1 }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertFalse(result.didMutate)
        XCTAssertEqual(updates, 0)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === pair.retained)
        XCTAssertTrue(proofs.allSatisfy(\.isCurrent))
        XCTAssertTrue(dialog.isValid)
        assertOriginalInputState(pair, hover: hover, fixture: fixture)
        fixture.runtime.pointerMoved(to: Point(x: grab.x, y: grab.y + 30))
        XCTAssertGreaterThan(pair.oldScroll.scrollOffset, offset, "The rejected disable must leave the grab active")
        XCTAssertTrue(hover.events.isEmpty)
    }

    func testUnsafeLaterSiblingRejectsTheWholeCheckedPlanBeforeEarlierAdoption() async throws {
        let pair = InputAdoptionRowPair(incomingEnabled: false)
        let earlier = inputRow("old earlier", tag: "earlier", y: 225)
        let incomingEarlier = inputRow("new earlier", tag: "earlier", y: 225)
        let editor = InputAdoptionTextController()
        earlier.textInputController = editor
        let hover = InputAdoptionHoverProbe()
        var grab = Point(x: 0, y: 0)
        let fixture = try InputAdoptionFixture(
            previous: [earlier, pair.retained], incoming: [incomingEarlier, pair.source], outside: hover.nodes,
            beforeAdmission: { runtime, provider in
                try hover.prime(in: runtime, provider: provider)
                grab = try InputAdoptionFixture.grabIndicator(in: runtime, of: pair.oldScroll)
            })
        defer { fixture.finish() }
        let earlierProof = earlier.captureLazyListAttachmentProof()
        let dialog = earlier.beginFileDialogPresentation(kind: .importer)
        let offset = pair.oldScroll.scrollOffset
        var earlierUpdates = 0
        incomingEarlier.onUpdatePlatformView = { _ in earlierUpdates += 1 }

        let result = fixture.reconcile()

        XCTAssertFalse(result.completed)
        XCTAssertFalse(result.didMutate)
        XCTAssertEqual(earlier.text, "old earlier")
        XCTAssertEqual(earlierUpdates, 0)
        XCTAssertTrue(earlierProof.isCurrent)
        XCTAssertTrue(dialog.isValid)
        XCTAssertEqual(editor.revokeCalls, 0)
        XCTAssertEqual(editor.detachCalls, 0)
        XCTAssertTrue(editor.isAuthorized(for: earlier))
        XCTAssertEqual(result.children.count, 2)
        XCTAssertTrue(result.children[0] === earlier)
        XCTAssertTrue(result.children[1] === pair.retained)
        assertOriginalInputState(pair, hover: hover, fixture: fixture)
        fixture.runtime.pointerMoved(to: Point(x: grab.x, y: grab.y + 30))
        XCTAssertGreaterThan(pair.oldScroll.scrollOffset, offset)
        XCTAssertTrue(hover.events.isEmpty)
    }

    func testDirectCheckedAdoptionRejectsAnActiveTopLevelScroller() async throws {
        let pair = InputAdoptionRowPair(incomingEnabled: false, nested: false)
        let hover = InputAdoptionHoverProbe()
        var grab = Point(x: 0, y: 0)
        let fixture = try InputAdoptionFixture(
            previous: [pair.retained], incoming: [pair.source], outside: hover.nodes,
            beforeAdmission: { runtime, provider in
                try hover.prime(in: runtime, provider: provider)
                grab = try InputAdoptionFixture.grabIndicator(in: runtime, of: pair.oldScroll)
            })
        defer { fixture.finish() }
        let offset = pair.oldScroll.scrollOffset

        let result = ComponentHost.adopt(
            source: pair.source, into: pair.retained, admission: fixture.admission)

        XCTAssertFalse(result.completed)
        XCTAssertFalse(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === pair.oldContent)
        assertOriginalInputState(pair, hover: hover, fixture: fixture)
        fixture.runtime.pointerMoved(to: Point(x: grab.x, y: grab.y + 30))
        XCTAssertGreaterThan(pair.oldScroll.scrollOffset, offset)
        XCTAssertTrue(hover.events.isEmpty)
    }

    func testDirectCheckedInputSetterRejectsActiveCaptureWithoutWritingTheFlag() async throws {
        let pair = InputAdoptionRowPair(incomingEnabled: false)
        let hover = InputAdoptionHoverProbe()
        var grab = Point(x: 0, y: 0)
        let fixture = try InputAdoptionFixture(
            previous: [pair.retained], incoming: [pair.source], outside: hover.nodes,
            beforeAdmission: { runtime, provider in
                try hover.prime(in: runtime, provider: provider)
                grab = try InputAdoptionFixture.grabIndicator(in: runtime, of: pair.oldScroll)
            })
        defer { fixture.finish() }
        let attachment = pair.oldScroll.captureLazyListAttachmentProof()
        let offset = pair.oldScroll.scrollOffset

        // Bypass Host's recursive preflight to exercise the setter's own
        // primitive guard with a still-current concrete admission.
        let completed = pair.oldScroll.reconcileScrollInputEnabled(false, admission: fixture.admission)

        XCTAssertFalse(completed)
        XCTAssertFalse(fixture.admission.didMutate)
        XCTAssertTrue(attachment.isCurrent)
        assertOriginalInputState(pair, hover: hover, fixture: fixture)
        fixture.runtime.pointerMoved(to: Point(x: grab.x, y: grab.y + 30))
        XCTAssertGreaterThan(pair.oldScroll.scrollOffset, offset)
        XCTAssertTrue(hover.events.isEmpty)
    }

    func testLateOutsideIndicatorCaptureRevokesAdmissionWithoutCancellingNewInput() async throws {
        let pair = InputAdoptionRowPair(incomingEnabled: false)
        let earlier = inputRow("old earlier", tag: "earlier", y: 225)
        let incomingEarlier = inputRow("new earlier", tag: "earlier", y: 225)
        let outside = InputAdoptionRowPair.makeScroll(text: "outside", contentText: "outside content", x: 300)
        let hover = InputAdoptionHoverProbe()
        var outsideGrab = Point(x: 0, y: 0)
        let fixture = try InputAdoptionFixture(
            previous: [earlier, pair.retained], incoming: [incomingEarlier, pair.source],
            outside: hover.nodes + [outside],
            beforeAdmission: { runtime, provider in
                try hover.prime(in: runtime, provider: provider)
                outsideGrab = try InputAdoptionFixture.thumbPoint(in: runtime, of: outside)
            })
        defer { fixture.finish() }
        var earlierUpdates = 0
        var laterUpdates = 0
        var currentBeforeCapture: Bool?
        var currentAfterCapture: Bool?
        incomingEarlier.onUpdatePlatformView = { [weak fixture] _ in
            guard let fixture else { return }
            earlierUpdates += 1
            currentBeforeCapture = fixture.admission.isCurrent
            fixture.runtime.pointerDown(at: outsideGrab)
            currentAfterCapture = fixture.admission.isCurrent
        }
        pair.source.onUpdatePlatformView = { _ in laterUpdates += 1 }

        let result = fixture.reconcile()

        XCTAssertEqual(earlierUpdates, 1)
        XCTAssertEqual(laterUpdates, 0)
        XCTAssertEqual(currentBeforeCapture, true)
        // Public pointerDown unconditionally performs layout, so the saved
        // layout pass is obsolete. This case covers partial/no-rollback
        // completion, not independent reachability of the setter's guard.
        XCTAssertEqual(currentAfterCapture, false)
        XCTAssertFalse(fixture.admission.isCurrent)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(earlier.text, "new earlier", "Do not roll back the earlier admitted property write")
        XCTAssertEqual(pair.retained.text, "old row")
        XCTAssertTrue(pair.oldScroll.isScrollInputEnabled)
        XCTAssertEqual(pair.oldContent.text, "old content")
        XCTAssertEqual(result.children.count, 2)
        XCTAssertTrue(result.children[0] === earlier)
        XCTAssertTrue(result.children[1] === pair.retained)
        XCTAssertTrue(hover.first.isHovered)
        XCTAssertFalse(hover.second.isHovered)
        XCTAssertTrue(hover.events.isEmpty)
        XCTAssertNotNil(fixture.provider.metadata)
        let offset = outside.scrollOffset
        fixture.runtime.pointerMoved(to: Point(x: outsideGrab.x, y: outsideGrab.y + 15))
        XCTAssertGreaterThan(outside.scrollOffset, offset)
        let firstMove = outside.scrollOffset
        fixture.runtime.pointerMoved(to: Point(x: outsideGrab.x, y: outsideGrab.y + 30))
        XCTAssertGreaterThan(outside.scrollOffset, firstMove, "The callback's new outside capture must survive")
        XCTAssertTrue(hover.events.isEmpty)
    }

    func testActiveIndicatorAllowsCheckedEnabledRefresh() async throws {
        let pair = InputAdoptionRowPair(incomingEnabled: true)
        let hover = InputAdoptionHoverProbe()
        var grab = Point(x: 0, y: 0)
        let fixture = try InputAdoptionFixture(
            previous: [pair.retained], incoming: [pair.source], outside: hover.nodes,
            beforeAdmission: { runtime, provider in
                try hover.prime(in: runtime, provider: provider)
                grab = try InputAdoptionFixture.grabIndicator(in: runtime, of: pair.oldScroll)
            })
        defer { fixture.finish() }
        let offset = pair.oldScroll.scrollOffset

        let result = fixture.reconcile()

        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertTrue(fixture.candidate.isCurrent)
        XCTAssertTrue(result.children.first === pair.retained)
        XCTAssertTrue(pair.retained.children.first === pair.oldScroll)
        XCTAssertTrue(pair.oldScroll.children.first === pair.oldContent)
        XCTAssertEqual(pair.retained.text, "new row")
        XCTAssertEqual(pair.oldContent.text, "new content")
        XCTAssertTrue(pair.oldScroll.isScrollInputEnabled)
        XCTAssertEqual(pair.oldScroll.scrollOffset, offset)
        XCTAssertTrue(hover.first.isHovered)
        XCTAssertTrue(hover.events.isEmpty)
        fixture.runtime.pointerMoved(to: Point(x: grab.x, y: grab.y + 30))
        XCTAssertGreaterThan(pair.oldScroll.scrollOffset, offset)
        XCTAssertTrue(hover.events.isEmpty)
    }

    func testInactiveScrollerAllowsCheckedDisableAndContentRefresh() async throws {
        let pair = InputAdoptionRowPair(incomingEnabled: false)
        let hover = InputAdoptionHoverProbe()
        let fixture = try InputAdoptionFixture(
            previous: [pair.retained], incoming: [pair.source], outside: hover.nodes,
            beforeAdmission: { runtime, provider in try hover.prime(in: runtime, provider: provider) })
        defer { fixture.finish() }

        let result = fixture.reconcile()

        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertTrue(fixture.candidate.isCurrent)
        XCTAssertEqual(pair.retained.text, "new row")
        XCTAssertEqual(pair.oldContent.text, "new content")
        XCTAssertFalse(pair.oldScroll.isScrollInputEnabled)
        XCTAssertTrue(result.children.first === pair.retained)
        XCTAssertTrue(pair.retained.children.first === pair.oldScroll)
        XCTAssertTrue(pair.oldScroll.children.first === pair.oldContent)
        XCTAssertTrue(hover.first.isHovered)
        XCTAssertFalse(hover.second.isHovered)
        XCTAssertTrue(hover.events.isEmpty)
        XCTAssertNotNil(fixture.provider.metadata)
    }

    func testOrdinaryDisableKeepsItsExistingCancellationBehavior() async throws {
        let pair = InputAdoptionRowPair(incomingEnabled: false)
        let hover = InputAdoptionHoverProbe()
        let fixture = try InputAdoptionFixture(
            previous: [pair.retained], incoming: [pair.source], outside: hover.nodes,
            beforeAdmission: { runtime, provider in
                try hover.prime(in: runtime, provider: provider, reentersOnExit: false)
                _ = try InputAdoptionFixture.grabIndicator(in: runtime, of: pair.oldScroll)
            })
        defer { fixture.finish() }

        let result = ComponentHost.reconcileChildren(
            of: fixture.container, oldChildren: fixture.container.children,
            newNodes: fixture.candidate.children, admission: nil)

        XCTAssertTrue(result.completed)
        XCTAssertFalse(pair.oldScroll.isScrollInputEnabled)
        XCTAssertEqual(pair.retained.text, "new row")
        XCTAssertEqual(pair.oldContent.text, "new content")
        XCTAssertEqual(hover.events, ["A.exit"])
        XCTAssertFalse(hover.first.isHovered)
        XCTAssertNotNil(fixture.provider.metadata)
        let stoppedOffset = pair.oldScroll.scrollOffset
        fixture.runtime.pointerMoved(to: hover.secondPoint)
        XCTAssertEqual(pair.oldScroll.scrollOffset, stoppedOffset)
        XCTAssertEqual(hover.events, ["A.exit", "B.enter"])
        fixture.runtime.pointerMoved(to: hover.secondPoint)
        XCTAssertEqual(hover.events, ["A.exit", "B.enter"], "The ordinary hover owner must not enter twice")
        fixture.runtime.pointerMoved(to: Point(x: 410, y: 250))
        XCTAssertEqual(hover.events, ["A.exit", "B.enter", "B.exit"])
        XCTAssertFalse(hover.second.isHovered)
    }

    func testCurrentSameInstanceAndGenerationRemainAllowedDuringActiveCapture() async throws {
        let pair = InputAdoptionRowPair(incomingEnabled: true)
        let hover = InputAdoptionHoverProbe()
        var grab = Point(x: 0, y: 0)
        // The factory explicitly returns the retained alias. No test assumes
        // a same-generation adapter rematerializes different factory content.
        let fixture = try InputAdoptionFixture(
            previous: [pair.retained], incoming: [pair.retained], outside: hover.nodes,
            beforeAdmission: { runtime, provider in
                try hover.prime(in: runtime, provider: provider)
                grab = try InputAdoptionFixture.grabIndicator(in: runtime, of: pair.oldScroll)
            })
        defer { fixture.finish() }
        let generation = try XCTUnwrap(fixture.provider.metadata?.generation)
        let offset = pair.oldScroll.scrollOffset
        XCTAssertTrue(fixture.candidate.children.first === pair.retained)
        XCTAssertEqual(fixture.factoryCalls, 1)

        let adopted = ComponentHost.adopt(
            source: pair.retained, into: pair.retained, admission: fixture.admission)

        XCTAssertTrue(adopted.completed)
        XCTAssertFalse(adopted.didMutate, "The direct same-instance shortcut does not start mutation")
        let reconciled = fixture.reconcile()
        XCTAssertTrue(reconciled.completed)
        // Child reconciliation retains its existing cumulative didMutate
        // behavior, even when every selected source is an actual retained alias.
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertTrue(fixture.candidate.isCurrent)
        XCTAssertEqual(fixture.provider.metadata?.generation, generation)
        XCTAssertEqual(fixture.factoryCalls, 1)
        XCTAssertTrue(reconciled.children.first === pair.retained)
        XCTAssertEqual(pair.oldContent.text, "old content")
        XCTAssertTrue(pair.oldScroll.isScrollInputEnabled)
        XCTAssertTrue(hover.first.isHovered)
        XCTAssertTrue(hover.events.isEmpty)
        fixture.runtime.pointerMoved(to: Point(x: grab.x, y: grab.y + 30))
        XCTAssertGreaterThan(pair.oldScroll.scrollOffset, offset)
        XCTAssertTrue(hover.events.isEmpty)
    }

    private func assertOriginalInputState(
        _ pair: InputAdoptionRowPair, hover: InputAdoptionHoverProbe, fixture: InputAdoptionFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(fixture.admission.isCurrent, file: file, line: line)
        XCTAssertTrue(fixture.candidate.isCurrent, file: file, line: line)
        XCTAssertNotNil(fixture.provider.metadata, file: file, line: line)
        XCTAssertEqual(
            pair.retained.text, pair.retained === pair.oldScroll ? "old scroll" : "old row", file: file, line: line)
        XCTAssertEqual(pair.retained.opacity, 0.8, file: file, line: line)
        XCTAssertEqual(pair.oldScroll.text, "old scroll", file: file, line: line)
        XCTAssertEqual(pair.oldContent.text, "old content", file: file, line: line)
        XCTAssertTrue(pair.oldScroll.isScrollInputEnabled, file: file, line: line)
        if pair.retained !== pair.oldScroll {
            XCTAssertTrue(pair.retained.children.first === pair.oldScroll, file: file, line: line)
            XCTAssertTrue(pair.oldScroll.parent === pair.retained, file: file, line: line)
        }
        XCTAssertTrue(pair.oldScroll.children.first === pair.oldContent, file: file, line: line)
        XCTAssertTrue(pair.oldContent.parent === pair.oldScroll, file: file, line: line)
        XCTAssertTrue(hover.first.isHovered, file: file, line: line)
        XCTAssertFalse(hover.second.isHovered, file: file, line: line)
        XCTAssertTrue(hover.events.isEmpty, file: file, line: line)
    }

    private func inputRow(_ text: String, tag: String, y: Double) -> ViewNode {
        let node = ViewNode(frame: Rect(x: 0, y: y, width: 140, height: 20), text: text)
        node.nodeTag = tag
        node.isHitTestVisible = false
        return node
    }
}

@MainActor
private struct InputAdoptionRowPair {
    let retained: ViewNode
    let source: ViewNode
    let oldScroll: ViewNode
    let newScroll: ViewNode
    let oldContent: ViewNode

    init(incomingEnabled: Bool, nested: Bool = true) {
        oldScroll = Self.makeScroll(text: "old scroll", contentText: "old content")
        newScroll = Self.makeScroll(text: "new scroll", contentText: "new content")
        newScroll.isScrollInputEnabled = incomingEnabled
        oldContent = oldScroll.children[0]
        if nested {
            retained = ViewNode(
                frame: Rect(x: 0, y: 0, width: 140, height: 220), text: "old row", children: [oldScroll])
            source = ViewNode(
                frame: Rect(x: 0, y: 0, width: 140, height: 220), text: "new row", children: [newScroll])
            retained.nodeTag = "row"
            source.nodeTag = "row"
        } else {
            retained = oldScroll
            source = newScroll
        }
        retained.isHitTestVisible = false
        source.isHitTestVisible = false
        retained.opacity = 0.8
        source.opacity = 0.4
    }

    static func makeScroll(text: String, contentText: String, x: Double = 10) -> ViewNode {
        let content = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 600), text: contentText)
        content.nodeTag = "content"
        content.isHitTestVisible = false
        let scroll = ViewNode(
            frame: Rect(x: x, y: 10, width: 100, height: 200), scrollAxis: .vertical,
            scrollOffset: 0, showsScrollIndicator: true, children: [content])
        scroll.text = text
        scroll.nodeTag = "scroll"
        scroll.retainedViewIdentity = .init(segments: [.explicit(.init("same-scroll-key"))])
        scroll.isHitTestVisible = false
        return scroll
    }
}

@MainActor
private final class InputAdoptionHoverProbe {
    let first = ViewNode(frame: Rect(x: 200, y: 10, width: 70, height: 50))
    let second = ViewNode(frame: Rect(x: 200, y: 80, width: 70, height: 50))
    var events: [String] = []
    var nodes: [ViewNode] { [first, second] }
    var firstPoint: Point { Point(x: first.frame.midX, y: first.frame.midY) }
    var secondPoint: Point { Point(x: second.frame.midX, y: second.frame.midY) }

    func prime(
        in runtime: RetainedViewRuntime, provider: RetainedLazyListDataSource<Int, [ViewNode]>,
        reentersOnExit: Bool = true
    ) throws {
        first.nodeTag = "outside-A"
        second.nodeTag = "outside-B"
        first.onPointerEnter = { [weak self] in self?.events.append("A.enter") }
        first.onPointerExit = { [weak self, weak runtime, weak provider] in
            guard let self else { return }
            events.append("A.exit")
            if reentersOnExit {
                // A one-shot exit is essential: nested pointerMoved observes
                // the old private hover owner until the outer helper returns.
                first.onPointerExit = nil
                provider?.close()
                runtime?.pointerMoved(to: secondPoint)
            }
        }
        second.onPointerEnter = { [weak self] in self?.events.append("B.enter") }
        second.onPointerExit = { [weak self] in self?.events.append("B.exit") }
        runtime.pointerMoved(to: firstPoint)
        guard first.isHovered, !second.isHovered else { throw InputAdoptionFixtureError.missingHover }
        events.removeAll()
    }
}

@MainActor
private final class InputAdoptionFixture {
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let container: ViewNode
    let runtime: RetainedViewRuntime
    let lease: InputAdoptionLease
    let epoch: InputAdoptionEpoch
    let candidate: RetainedLazyListRuntimeAdapter.Candidate
    let admission: RetainedLazyListAdoptionAdmission
    private let factoryCounter: InputAdoptionFactoryCounter
    private let fixtureRoots: [ViewNode]
    private var didFinish = false
    var factoryCalls: Int { factoryCounter.calls }

    init(
        previous: [ViewNode], incoming: [ViewNode], outside: [ViewNode],
        beforeAdmission: @MainActor (RetainedViewRuntime, RetainedLazyListDataSource<Int, [ViewNode]>) throws -> Void
    ) throws {
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        let factoryCounter = InputAdoptionFactoryCounter()
        guard
            provider.replaceData(
                [0], id: \.self, identityRoot: .init(segments: [.role(.content)]),
                rowContent: { _, _ in
                    factoryCounter.calls += 1
                    return incoming
                })
        else { throw InputAdoptionFixtureError.setup }
        let row = try XCTUnwrap(provider.metadata?.rows.first)
        let request = try XCTUnwrap(provider.request(for: row.token))
        let prefix = try XCTUnwrap(provider.identityPrefix(for: request))
        let previousPaths = previous.enumerated().map { Self.fixturePath(for: $0.element, index: $0.offset) }
        let incomingPaths = incoming.enumerated().map { Self.fixturePath(for: $0.element, index: $0.offset) }
        var configured: Set<ObjectIdentifier> = []
        for (nodes, paths) in [(previous, previousPaths), (incoming, incomingPaths)] {
            for (index, node) in nodes.enumerated() where configured.insert(ObjectIdentifier(node)).inserted {
                node.retainedViewIdentity = prefix.appending(contentsOf: paths[index])
            }
        }
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 160, height: 250))
        container.isHitTestVisible = false
        for node in previous { container.addChild(node) }
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 420, height: 260))
        root.isHitTestVisible = false
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 0 }
        root.addChild(container)
        for node in outside { root.addChild(node) }
        // Layout, ordinary hover, and any initial thumb grab must precede the
        // adapter and its captured layout-pass admission. No hidden later
        // query is needed to fabricate a private active-capture state.
        _ = runtime.renderScene()
        try beforeAdmission(runtime, provider)
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 250, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let lease = InputAdoptionLease()
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        guard adapter.ownsAttachment(container) else { throw InputAdoptionFixtureError.setup }
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: 160, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 250))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let epoch = InputAdoptionEpoch()
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
            }
        }
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget, admission: admission),
            admission.installCandidate(candidate), epoch.willAdopt(), admission.isCurrent
        else { throw InputAdoptionFixtureError.setup }
        self.provider = provider
        self.adapter = adapter
        self.container = container
        self.runtime = runtime
        self.lease = lease
        self.epoch = epoch
        self.candidate = candidate
        self.admission = admission
        self.factoryCounter = factoryCounter
        self.fixtureRoots = previous + incoming + outside + [container, root]
        setupCompleted = true
    }

    static func thumbPoint(in runtime: RetainedViewRuntime, of node: ViewNode) throws -> Point {
        for draw in runtime.currentPrepaintState.deferredDraws {
            if case .scrollIndicator(let payload) = draw.payload, payload.node === node {
                guard payload.track.travel > 0 else { throw InputAdoptionFixtureError.missingIndicator }
                return Point(x: payload.track.indicatorRect.midX, y: payload.track.indicatorRect.midY)
            }
        }
        throw InputAdoptionFixtureError.missingIndicator
    }

    static func grabIndicator(in runtime: RetainedViewRuntime, of node: ViewNode) throws -> Point {
        let grab = try thumbPoint(in: runtime, of: node)
        let initialOffset = node.scrollOffset
        runtime.pointerDown(at: grab)
        runtime.pointerMoved(to: Point(x: grab.x, y: grab.y + 4))
        guard node.scrollOffset > initialOffset else { throw InputAdoptionFixtureError.missingCapture }
        return grab
    }

    private static func fixturePath(for node: ViewNode, index: Int) -> [RetainedViewIdentity.Segment] {
        if let identity = node.retainedViewIdentity { return [.role(.content)] + identity.segments }
        if let tag = node.nodeTag { return [.role(.content), .explicit(.init(tag))] }
        return [.role(.content), .slot(index)]
    }

    func reconcile() -> RetainedLazyListAdoptionResult {
        ComponentHost.reconcileChildren(
            of: container, oldChildren: container.children, newNodes: candidate.children, admission: admission)
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        var pending = fixtureRoots
        var visited: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            pending.append(contentsOf: node.children)
            node.onPointerEnter = nil
            node.onPointerExit = nil
            node.onPointerMove = nil
            node.onUpdatePlatformView = nil
            node.onDismantlePlatformView = nil
        }
        runtime.clock = { 0 }
        runtime.pointerCancelled()
        provider.close()
        candidate.discardBuiltContent()
        if admission.didMutate { epoch.commit() } else { epoch.abandon() }
        epoch.finishAfterCallbacks()
        runtime.retainedBuildCoordinator.finishBuild()
    }
}

private enum InputAdoptionFixtureError: Error {
    case setup, missingHover, missingIndicator, missingCapture
}

@MainActor
private final class InputAdoptionFactoryCounter {
    var calls = 0
}

@MainActor
private final class InputAdoptionLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { InputAdoptionEpoch() }
}

@MainActor
private final class InputAdoptionEpoch: RetainedBuildEpoch {
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
private final class InputAdoptionTextController: RetainedTextInputController {
    private weak var owner: ViewNode?
    private var authorized = false
    private(set) var revokeCalls = 0
    private(set) var detachCalls = 0
    func attach(to node: ViewNode) {
        owner = node
        authorized = true
    }
    func isAuthorized(for node: ViewNode) -> Bool { owner === node && authorized }
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func revokeOwnership(from node: ViewNode) {
        guard owner === node, authorized else { return }
        authorized = false
        revokeCalls += 1
    }
    func detach(from node: ViewNode) {
        guard owner === node else { return }
        authorized = false
        owner = nil
        detachCalls += 1
    }
}
