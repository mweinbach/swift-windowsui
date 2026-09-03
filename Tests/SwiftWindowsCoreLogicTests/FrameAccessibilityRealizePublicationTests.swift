import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Physical retained rows exercise Realize without logical List IDs or an HWND.
/// The queued callback runs inside the original Realize layout query.
@MainActor
final class FrameAccessibilityRealizePublicationTests: XCTestCase {
    func testFramedPhysicalRealizeRejectsPublicationChangedByInitialLayout() async throws {
        let fixture = try FrameRealizePublicationFixture(framed: true)
        defer { fixture.close() }
        let original = try fixture.snapshot()
        let request = try XCTUnwrap(fixture.row.currentAccessibilitySemanticRequest)
        let attachment = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.semantic))
        XCTAssertTrue(request.semanticNode === fixture.semantic)
        XCTAssertTrue(request.isCurrent(in: fixture.runtime))
        XCTAssertTrue(original.isVirtualizedPlaceholder)
        XCTAssertNotEqual(original.id, UIAProviderBridge.rootElementID)
        var callbacks = 0
        var isRealizing = false
        fixture.countClockCalls()
        fixture.runtime.scheduleAfterLayout(key: "frame-realize-publication-change") { [weak fixture] in
            callbacks += 1
            XCTAssertTrue(isRealizing, "The publication must change inside the initial Realize query")
            guard let fixture else { return XCTFail("The original fixture must remain alive") }
            XCTAssertTrue(request.isCurrent(in: fixture.runtime))
            XCTAssertTrue(fixture.semantic.parent === fixture.row)
            fixture.row.accessibilityLabel = "Updated frame label"
            XCTAssertFalse(request.isCurrent(in: fixture.runtime))
            XCTAssertTrue(request.isStructurallyCurrent(in: fixture.runtime))
            XCTAssertTrue(fixture.runtime.isAccessibilityAttachmentCurrent(attachment))
            let current = fixture.row.currentAccessibilitySemanticRequest
            XCTAssertTrue(current?.element === request.element)
            XCTAssertEqual(current?.metadata.label, "Updated frame label")
        }
        XCTAssertEqual(callbacks, 0)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)

        isRealizing = true
        let completed = fixture.source.uiaRealizeVirtualizedItem(elementID: original.id)
        isRealizing = false

        XCTAssertFalse(completed)
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(fixture.probe.clockCalls, 0, "A superseded request must stop before the scroll clock")
        XCTAssertEqual(fixture.scroll.scrollOffset, 0, accuracy: 0.0001)
        XCTAssertTrue(fixture.row.isLayoutDeferredByVirtualization)
        XCTAssertTrue(fixture.runtime.isAccessibilityAttachmentCurrent(attachment))
        XCTAssertFalse(request.isCurrent(in: fixture.runtime))
        XCTAssertTrue(request.isStructurallyCurrent(in: fixture.runtime))
        XCTAssertEqual(fixture.probe.activations, 0)
        XCTAssertNil(fixture.runtime.focusedNode)
        let current = try fixture.snapshot()
        XCTAssertEqual(current.id, original.id, "Metadata changes preserve the element, not the old operation")
        XCTAssertEqual(current.name, "Updated frame label")
        XCTAssertTrue(current.isVirtualizedPlaceholder)
    }

    func testQueuedPhysicalRealizeSucceedsForUnchangedFramedAndOrdinaryRows() async throws {
        for framed in [true, false] {
            let fixture = try FrameRealizePublicationFixture(framed: framed)
            defer { fixture.close() }
            let original = try fixture.snapshot()
            let request = fixture.row.currentAccessibilitySemanticRequest
            XCTAssertEqual(request != nil, framed)
            XCTAssertTrue(original.isVirtualizedPlaceholder)
            var callbacks = 0
            var isRealizing = false
            fixture.countClockCalls()
            fixture.runtime.scheduleAfterLayout(key: "frame-realize-unchanged-query") {
                callbacks += 1
                XCTAssertTrue(isRealizing, "The original request must consume the queued layout callback")
            }
            XCTAssertEqual(callbacks, 0)

            isRealizing = true
            let completed = fixture.source.uiaRealizeVirtualizedItem(elementID: original.id)
            isRealizing = false

            XCTAssertTrue(completed, "framed: \(framed)")
            XCTAssertEqual(callbacks, 1)
            XCTAssertEqual(fixture.probe.clockCalls, 1)
            XCTAssertEqual(fixture.scroll.scrollOffset, 410, accuracy: 0.0001)
            XCTAssertTrue(request?.isCurrent(in: fixture.runtime) != false)
            XCTAssertEqual(fixture.probe.activations, 0)
            XCTAssertNil(fixture.runtime.focusedNode)
            fixture.settle()
            let settledClockCalls = fixture.probe.clockCalls
            XCTAssertFalse(fixture.row.isLayoutDeferredByVirtualization)
            let visible = try fixture.snapshot()
            XCTAssertEqual(visible.id, original.id)
            XCTAssertFalse(visible.isVirtualizedPlaceholder)
            XCTAssertFalse(fixture.source.uiaRealizeVirtualizedItem(elementID: original.id))
            XCTAssertEqual(callbacks, 1)
            XCTAssertEqual(
                fixture.probe.clockCalls, settledClockCalls, "An already visible row must not start another scroll")
            XCTAssertEqual(fixture.scroll.scrollOffset, 410, accuracy: 0.0001)
        }
    }
}

@MainActor
private final class FrameRealizePublicationProbe {
    var clockCalls = 0
    var activations = 0
}

@MainActor
private final class FrameRealizePublicationFixture {
    let runtime: RetainedViewRuntime
    let source: RuntimeUIAElementTreeSource
    let scroll: ViewNode
    let row: ViewNode
    let semantic: ViewNode
    let probe: FrameRealizePublicationProbe

    init(framed: Bool) throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 240))
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 100 }
        let probe = FrameRealizePublicationProbe()
        let row: ViewNode
        let semantic: ViewNode
        if framed {
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 320, height: 240) }, invalidateHandler: {})
            row = Button("Framed physical row") { probe.activations += 1 }
                .frame(width: 120, height: 30)
                .accessibilityLabel("Original frame label")
                .accessibilityIdentifier("realize-publication-subject")
                .makeComponent(context: context).makeNode(runtime: runtime)
            semantic = try XCTUnwrap(row.children.first)
            XCTAssertNil(row.selectedContentRole)
        } else {
            row = ViewNode(
                preferredSize: Size(width: 120, height: 30), isHitTestVisible: false,
                accessibilityLabel: "Ordinary physical row")
            row.accessibilityIdentifier = "realize-publication-subject"
            semantic = row
        }
        var rows = (0..<20).map { index in
            ViewNode(
                preferredSize: Size(width: 120, height: 30), isHitTestVisible: false,
                accessibilityLabel: "Physical row \(index)")
        }
        rows[16] = row
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 100), clipsToBounds: true,
            layoutMode: .lazyStack(.vertical(spacing: 0)), scrollAxis: .vertical, children: rows)
        root.addChild(scroll)
        self.runtime = runtime
        self.source = RuntimeUIAElementTreeSource(runtime: runtime)
        self.scroll = scroll
        self.row = row
        self.semantic = semantic
        self.probe = probe
        _ = runtime.renderScene()
        XCTAssertNil(scroll.retainedLazyListAdapter, "This fixture must use physical provider IDs")
        XCTAssertTrue(row.isLayoutDeferredByVirtualization)
        XCTAssertEqual(scroll.scrollOffset, 0)
    }

    func snapshot() throws -> UIAElementSnapshot {
        let matches = source.uiaElementSnapshots().filter { $0.automationID == "realize-publication-subject" }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }

    func countClockCalls() {
        probe.clockCalls = 0
        runtime.clock = { [weak probe] in
            probe?.clockCalls += 1
            return 100
        }
    }

    func settle() { XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root)) }

    func close() {
        runtime.clock = { 100 }
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}
