import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A physical framed placeholder first reveals its 300-point row. The next
/// retained render refines that same request to the actual top-aligned Button.
@MainActor
final class FrameAccessibilityPreciseAlignmentTests: XCTestCase {
    func testQueuedFrameRealizeRejectsBetweenReturnPublicationAndDeclarationChanges() async throws {
        for mutation in FramePreciseMutation.allCases {
            let fixture = try FramePreciseFixture(framed: true)
            defer { fixture.close() }
            let request = try fixture.beginFramedRealize()
            let attachment = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.semantic))
            fixture.mutate(mutation)
            XCTAssertFalse(request.isCurrent(in: fixture.runtime))
            XCTAssertTrue(fixture.runtime.isAccessibilityAttachmentCurrent(attachment))
            fixture.countClockCalls()

            fixture.render()

            fixture.assertFineGeometry()
            XCTAssertEqual(fixture.probe.clockCalls, 0, mutation.rawValue)
            XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001, mutation.rawValue)
            XCTAssertTrue(fixture.runtime.isAccessibilityAttachmentCurrent(attachment))
            fixture.query()
            fixture.render()
            XCTAssertEqual(fixture.probe.clockCalls, 0)
            XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
            XCTAssertEqual(fixture.probe.activations, 0)
        }
    }

    func testQueuedFrameRealizeRechecksOriginalProofAfterClock() async throws {
        for mutation in FramePreciseMutation.allCases {
            let fixture = try FramePreciseFixture(framed: true)
            defer { fixture.close() }
            let request = try fixture.beginFramedRealize()
            let attachment = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.semantic))
            fixture.probe.clockCalls = 0
            fixture.runtime.clock = { [weak fixture] in
                guard let fixture else {
                    XCTFail("The original fixture must survive the clock")
                    return 100
                }
                fixture.probe.clockCalls += 1
                fixture.runtime.clock = { 100 }
                XCTAssertTrue(request.isCurrent(in: fixture.runtime))
                XCTAssertEqual(fixture.scroll.scrollOffset, 600)
                fixture.mutate(mutation)
                XCTAssertFalse(request.isCurrent(in: fixture.runtime))
                XCTAssertTrue(fixture.runtime.isAccessibilityAttachmentCurrent(attachment))
                return 100
            }

            fixture.render()

            fixture.assertFineGeometry()
            XCTAssertEqual(fixture.probe.clockCalls, 1, mutation.rawValue)
            XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001, mutation.rawValue)
            fixture.query()
            fixture.render()
            XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
            XCTAssertEqual(fixture.probe.activations, 0)
        }
    }

    func testQueuedFrameRealizeRejectsEqualOffsetIntentSupersessionFromClock() async throws {
        let fixture = try FramePreciseFixture(framed: true)
        defer { fixture.close() }
        let request = try fixture.beginFramedRealize()
        fixture.probe.clockCalls = 0
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture else {
                XCTFail("The original fixture must survive the clock")
                return 100
            }
            fixture.probe.clockCalls += 1
            fixture.runtime.clock = { 100 }
            XCTAssertTrue(request.isCurrent(in: fixture.runtime))
            XCTAssertEqual(fixture.scroll.scrollOffset, 600)
            // The existing authored setter revokes intent even at equal values.
            fixture.scroll.scrollOffset = 600
            XCTAssertTrue(request.isCurrent(in: fixture.runtime))
            return 100
        }

        fixture.render()

        fixture.assertFineGeometry()
        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertTrue(request.isCurrent(in: fixture.runtime))
        XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
        fixture.query()
        fixture.render()
        XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
    }

    func testQueuedFrameRealizeDoesNotCancelAnInterveningPointerSequence() async throws {
        let fixture = try FramePreciseFixture(framed: true)
        defer { fixture.close() }
        let request = try fixture.beginFramedRealize()
        var grabPoint: Point?
        fixture.probe.clockCalls = 0
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture else {
                XCTFail("The original fixture must survive the clock")
                return 100
            }
            fixture.probe.clockCalls += 1
            // Input has its own clocks. It must not recursively rerun this
            // one precise-alignment callback.
            fixture.runtime.clock = { 100 }
            XCTAssertTrue(request.isCurrent(in: fixture.runtime))
            XCTAssertEqual(fixture.scroll.scrollOffset, 600)
            // Existing pointer routing refreshes prepaint. The pending record
            // is already removed from its queue while this clock is running.
            fixture.runtime.pointerMoved(to: Point(x: 200, y: 200))
            do { grabPoint = try fixture.beginIndicatorDrag() } catch {
                XCTFail("A real retained scroll thumb must be available: \(error)")
            }
            XCTAssertEqual(fixture.scroll.scrollOffset, 600)
            return 100
        }

        fixture.render()

        let point = try XCTUnwrap(grabPoint)
        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertTrue(request.isCurrent(in: fixture.runtime))
        XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
        // The same thumb grab must remain active after the refinement refuses.
        let moved = Point(x: point.x, y: point.y - 5)
        fixture.runtime.pointerMoved(to: moved)
        let draggedOffset = fixture.scroll.scrollOffset
        XCTAssertLessThan(draggedOffset, 600)
        XCTAssertGreaterThan(draggedOffset, 400)
        fixture.runtime.pointerUp(at: moved)
        fixture.query()
        fixture.render()
        XCTAssertEqual(fixture.scroll.scrollOffset, draggedOffset, accuracy: 0.0001)
        XCTAssertEqual(fixture.probe.activations, 0)
    }

    func testUnchangedQueuedFrameAndOrdinaryNestedScrollKeepPreciseAlignment() async throws {
        for framed in [true, false] {
            let fixture = try FramePreciseFixture(framed: framed)
            defer { fixture.close() }
            let request: RetainedAccessibilitySemanticRequest?
            if framed {
                request = try fixture.beginFramedRealize()
            } else {
                request = nil
                XCTAssertNil(fixture.row.currentAccessibilitySemanticRequest)
                XCTAssertTrue(fixture.runtime.scrollToDescendant(fixture.semantic, transaction: Transaction()))
                XCTAssertEqual(fixture.scroll.scrollOffset, 600, accuracy: 0.0001)
            }
            fixture.countClockCalls()

            fixture.render()

            fixture.assertFineGeometry()
            XCTAssertEqual(fixture.probe.clockCalls, 1, "framed: \(framed)")
            XCTAssertEqual(fixture.scroll.scrollOffset, 400, accuracy: 0.0001, "framed: \(framed)")
            XCTAssertTrue(request?.isCurrent(in: fixture.runtime) != false)
            fixture.query()
            fixture.render()
            XCTAssertEqual(fixture.probe.clockCalls, 1, "A settled correction must not be repeated")
            XCTAssertEqual(fixture.scroll.scrollOffset, 400, accuracy: 0.0001)
            XCTAssertEqual(fixture.probe.activations, 0)
        }
    }

    func testPendingFrameRequestDoesNotRetainActionCapturesOrRuntime() async throws {
        var fixture: FramePreciseFixture? = try FramePreciseFixture(framed: true)
        let probe = try XCTUnwrap(fixture?.probe)
        fixture?.installActionCapture()
        XCTAssertNotNil(probe.payload)
        let request = try XCTUnwrap(fixture).beginFramedRealize()
        XCTAssertEqual(request.actions.count, 1)
        weak var runtime = fixture?.runtime
        weak var root = fixture?.runtime.root
        weak var row = fixture?.row
        weak var inner = fixture?.inner
        weak var semantic = fixture?.semantic

        fixture?.row.accessibilityActions = []

        XCTAssertEqual(probe.cleanups, 1)
        XCTAssertNil(probe.payload, "Pending refinement must not copy the old action handler")
        XCTAssertFalse(request.isCurrent)
        XCTAssertNotNil(runtime)
        // Do not drain/cancel the pending queue before dropping its actual
        // runtime. A saved request must keep only weak physical/action owners.
        fixture = nil
        XCTAssertNil(runtime)
        XCTAssertNil(root)
        XCTAssertNil(row)
        XCTAssertNil(inner)
        XCTAssertNil(semantic)
        XCTAssertNil(request.semanticNode)
        XCTAssertNil(request.actions.first?.owner)
        XCTAssertFalse(request.isCurrent)
        XCTAssertEqual(probe.cleanups, 1)
    }

    func testSupersededOrRemovedFrameAlignmentCannotReappear() async throws {
        do {
            let fixture = try FramePreciseFixture(framed: true)
            defer { fixture.close() }
            let request = try fixture.beginFramedRealize()
            fixture.scroll.scrollOffset = 450
            fixture.countClockCalls()

            fixture.render()
            fixture.query()
            fixture.render()

            XCTAssertTrue(request.isCurrent(in: fixture.runtime))
            XCTAssertEqual(fixture.scroll.scrollOffset, 450, accuracy: 0.0001)
            XCTAssertEqual(fixture.probe.clockCalls, 0)
        }
        do {
            var fixture: FramePreciseFixture? = try FramePreciseFixture(framed: true)
            fixture?.installActionCapture()
            let request = try XCTUnwrap(fixture).beginFramedRealize()
            let runtime = try XCTUnwrap(fixture?.runtime)
            let scroll = try XCTUnwrap(fixture?.scroll)
            let probe = try XCTUnwrap(fixture?.probe)
            weak var row = fixture?.row
            weak var semantic = fixture?.semantic
            XCTAssertNotNil(probe.payload)
            fixture?.row.removeFromParent()
            scroll.scrollOffset = 40
            XCTAssertFalse(request.isCurrent(in: runtime))
            fixture?.countClockCalls()
            fixture = nil

            _ = runtime.renderFrame(at: 100)
            XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
            _ = runtime.renderFrame(at: 100)

            XCTAssertEqual(scroll.scrollOffset, 40, accuracy: 0.0001)
            XCTAssertEqual(probe.clockCalls, 0)
            XCTAssertNil(row)
            XCTAssertNil(semantic)
            XCTAssertNil(probe.payload)
            XCTAssertEqual(probe.cleanups, 1)
            XCTAssertNil(request.semanticNode)
            runtime.clock = { 100 }
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            runtime.root.removeAllChildren()
        }
    }

    func testPreciseAlignmentHistoryCleanupCannotContinueTheOldFrameRequest() async throws {
        let fixture = try FramePreciseFixture(framed: true)
        defer { fixture.close() }
        let request = try fixture.beginFramedRealize()
        fixture.installPhaseHistory()
        XCTAssertNotNil(fixture.probe.payload)
        XCTAssertEqual(fixture.probe.cleanups, 0)
        fixture.countClockCalls()

        fixture.render()

        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertEqual(fixture.probe.cleanups, 1)
        XCTAssertNil(fixture.probe.payload, "Phase cleanup must finish before the render returns")
        XCTAssertEqual(fixture.probe.offsetsAtCleanup, [400], "The accepted fine write precedes history retirement")
        XCTAssertFalse(request.isCurrent(in: fixture.runtime))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0, accuracy: 0.0001)
        fixture.query()
        fixture.render()
        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertEqual(fixture.probe.cleanups, 1)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0, accuracy: 0.0001)
        XCTAssertEqual(fixture.probe.activations, 0)
    }
}

private enum FramePreciseMutation: String, CaseIterable {
    case label
    case declaredOwner
}

@MainActor
private final class FramePreciseProbe {
    var clockCalls = 0
    var activations = 0
    var cleanups = 0
    var offsetsAtCleanup: [Double] = []
    weak var payload: FramePrecisePayload?
}

@MainActor
private final class FramePrecisePayload {
    private let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

private struct FramePreciseObservedValue: Equatable {
    let marker: Int
    let payload: FramePrecisePayload?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.marker == rhs.marker }
}

@MainActor
private final class FramePreciseFixture {
    let runtime: RetainedViewRuntime
    let source: RuntimeUIAElementTreeSource
    let scroll: ViewNode
    let row: ViewNode
    let inner: ViewNode
    let semantic: ViewNode
    let probe: FramePreciseProbe

    init(framed: Bool) throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 240))
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 100 }
        let probe = FramePreciseProbe()
        let row: ViewNode
        let inner: ViewNode
        let semantic: ViewNode
        if framed {
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 240) }, invalidateHandler: {})
            row = Button("Precise frame target") { probe.activations += 1 }
                .frame(width: 80, height: 20, alignment: .topLeading)
                .frame(width: 80, height: 300, alignment: .topLeading)
                .accessibilityLabel("Original precise frame")
                .accessibilityIdentifier("precise-frame-subject")
                .makeComponent(context: context).makeNode(runtime: runtime)
            inner = try XCTUnwrap(row.children.first)
            semantic = try XCTUnwrap(inner.children.first)
            XCTAssertTrue(row.accessibilityDeclaredFrameContent === inner)
            XCTAssertTrue(inner.accessibilityDeclaredFrameContent === semantic)
        } else {
            semantic = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 20), preferredSize: Size(width: 80, height: 20),
                isHitTestVisible: false, accessibilityLabel: "Ordinary nested target")
            inner = semantic
            row = ViewNode(
                preferredSize: Size(width: 80, height: 300), isHitTestVisible: false, children: [semantic])
        }
        let preceding = (0..<10).map { _ in
            ViewNode(preferredSize: Size(width: 80, height: 40), isHitTestVisible: false)
        }
        let trailing = (0..<4).map { _ in
            ViewNode(preferredSize: Size(width: 80, height: 40), isHitTestVisible: false)
        }
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100), clipsToBounds: true,
            layoutMode: .lazyStack(.vertical(spacing: 0)), scrollAxis: .vertical,
            children: preceding + [row] + trailing)
        scroll.showsScrollIndicator = true
        scroll.scrollIndicatorAutoHides = false
        root.addChild(scroll)
        self.runtime = runtime
        self.source = RuntimeUIAElementTreeSource(runtime: runtime)
        self.scroll = scroll
        self.row = row
        self.inner = inner
        self.semantic = semantic
        self.probe = probe
        _ = runtime.renderFrame(at: 100)
        XCTAssertNil(scroll.retainedLazyListAdapter, "Only physical provider IDs belong in this fixture")
        XCTAssertTrue(row.isLayoutDeferredByVirtualization)
        XCTAssertEqual(row.resolvedFrame.minY, 400, accuracy: 0.0001)
        XCTAssertEqual(row.resolvedFrame.size.height, 300, accuracy: 0.0001)
        XCTAssertEqual(scroll.scrollOffset, 0)
    }

    func beginFramedRealize() throws -> RetainedAccessibilitySemanticRequest {
        let matches = source.uiaElementSnapshots().filter { $0.automationID == "precise-frame-subject" }
        XCTAssertEqual(matches.count, 1)
        let snapshot = try XCTUnwrap(matches.first)
        let request = try XCTUnwrap(row.currentAccessibilitySemanticRequest)
        XCTAssertTrue(request.semanticNode === semantic)
        XCTAssertTrue(request.isCurrent(in: runtime))
        XCTAssertTrue(snapshot.isVirtualizedPlaceholder)
        XCTAssertNotEqual(snapshot.id, UIAProviderBridge.rootElementID)
        XCTAssertTrue(source.uiaRealizeVirtualizedItem(elementID: snapshot.id))
        XCTAssertTrue(request.isCurrent(in: runtime))
        XCTAssertEqual(scroll.scrollOffset, 600, accuracy: 0.0001)
        XCTAssertTrue(row.isLayoutDeferredByVirtualization)
        XCTAssertEqual(probe.activations, 0)
        return request
    }

    func mutate(_ mutation: FramePreciseMutation) {
        switch mutation {
        case .label:
            row.accessibilityLabel = "Superseding precise frame"
        case .declaredOwner:
            // Retire and restore the explicit declaration without touching the
            // actual physical child path. A getter cannot revive its old owner.
            row.replaceAccessibilityFrameDeclaration(content: nil)
            row.declareAccessibilityFrameContent(inner)
            XCTAssertTrue(row.accessibilityDeclaredFrameContent === inner)
            XCTAssertTrue(inner.parent === row)
            XCTAssertTrue(semantic.parent === inner)
        }
    }

    func countClockCalls() {
        probe.clockCalls = 0
        runtime.clock = { [weak probe] in
            probe?.clockCalls += 1
            return 100
        }
    }

    func render() { _ = runtime.renderFrame(at: 100) }
    func query() { XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root)) }

    func assertFineGeometry() {
        XCTAssertFalse(row.isLayoutDeferredByVirtualization)
        XCTAssertEqual(row.resolvedFrame.minY, 400, accuracy: 0.0001)
        XCTAssertEqual(row.resolvedFrame.size.height, 300, accuracy: 0.0001)
        XCTAssertEqual(inner.resolvedFrame.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(inner.resolvedFrame.size.height, 20, accuracy: 0.0001)
        XCTAssertEqual(semantic.resolvedFrame.minY, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(semantic.resolvedFrame.size.height, 0)
        XCTAssertLessThanOrEqual(semantic.resolvedFrame.size.height, 100)
    }

    func beginIndicatorDrag() throws -> Point {
        let track = try XCTUnwrap(
            runtime.currentPrepaintState.deferredDraws.compactMap { draw -> ScrollIndicatorTrack? in
                guard case .scrollIndicator(let payload) = draw.payload, payload.node === scroll else { return nil }
                return payload.track
            }.first)
        XCTAssertGreaterThan(track.travel, 0)
        let point = Point(x: track.indicatorRect.midX, y: track.indicatorRect.midY)
        runtime.pointerDown(at: point)
        return point
    }

    @inline(never)
    func installActionCapture() {
        let payload = FramePrecisePayload { [weak probe] in probe?.cleanups += 1 }
        probe.payload = payload
        row.accessibilityActions = [
            RetainedAccessibilityAction(name: "Retained frame capture") { [payload] in withExtendedLifetime(payload) {}
            }
        ]
    }

    @inline(never)
    func installPhaseHistory() {
        scroll.observeScrollGeometry(
            of: { _ in FramePreciseObservedValue(marker: 0, payload: nil) }, action: { _, _ in })
        scroll.observeScrollPhase { _, _, _ in }
        let payload = FramePrecisePayload { [weak self, weak probe] in
            guard let self, let probe else { return XCTFail("Phase history must retire while its fixture is alive") }
            probe.cleanups += 1
            probe.offsetsAtCleanup.append(scroll.scrollOffset)
            row.accessibilityLabel = "Changed by phase history cleanup"
            scroll.scrollOffset = 0
        }
        probe.payload = payload
        // This is the existing observed-value storage, not a new admission
        // hook. First phase source selection retires the opaque old value.
        scroll.scrollObserverStorage?.geometry.first?.previousValue =
            FramePreciseObservedValue(marker: 1, payload: payload)
    }

    func close() {
        runtime.clock = { 100 }
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
        runtime.pointerCancelled()
        scroll.scrollObserverStorage = nil
        runtime.root.removeAllChildren()
    }
}
