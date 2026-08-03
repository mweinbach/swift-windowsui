import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// WS-20: `LazyVStack` was lazy in name only. The runtime had no
/// virtualization concept at all, so a 5,000-row list ran a full recursive
/// `layoutSubtree` into every row on every layout pass regardless of where
/// the scroll viewport was.
///
/// `.lazyStack` is that concept. Placement is unchanged — a stack cannot
/// know where row 900 goes without knowing how tall rows 0…899 are, and the
/// per-node measurement cache is what keeps that shallow — but the recursive
/// descent into a row's subtree is skipped while the viewport (plus a
/// viewport of overscan) cannot reach it.
///
/// Two things are asserted here, and the second matters more than the first:
/// that the work is bounded, and that the *picture is unchanged*.
@MainActor
final class LazyStackVirtualizationTests: XCTestCase {

    private static let rowCount = 400
    private static let rowHeight: Double = 24
    private static let viewportSize = IntSize(width: 240, height: 200)

    private struct Rows: View {
        let count: Int
        let lazyStack: Bool

        var body: some View {
            ScrollView {
                if lazyStack {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<count, id: \.self) { index in
                            row(index)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(0..<count, id: \.self) { index in
                            row(index)
                        }
                    }
                }
            }
        }

        private func row(_ index: Int) -> some View {
            HStack(spacing: 4) {
                Text("row \(index)")
                Spacer()
                Text("\(index * 7)")
            }
            .frame(width: 220, height: LazyStackVirtualizationTests.rowHeight)
            .background(Color(red: 0.15, green: 0.18, blue: 0.24, alpha: 1))
        }
    }

    private func snapshot(lazyStack: Bool) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: Rows(count: Self.rowCount, lazyStack: lazyStack),
            size: Self.viewportSize,
            displayScale: 1)
    }

    // MARK: - Bounded work

    func testLazyStackSkipsLayoutForRowsTheViewportCannotReach() async {
        let lazySnapshot = snapshot(lazyStack: true)
        let skipped = lazySnapshot.runtime.virtualizedLayoutSkipCount

        // The viewport is 200pt tall with 24pt rows, and the overscan is a
        // full viewport on each side: ~25 rows are in range, ~375 are not.
        XCTAssertGreaterThan(
            skipped, Self.rowCount / 2,
            "a lazy stack must skip the recursive layout of rows the viewport plus overscan cannot reach; "
                + "skipped \(skipped) of \(Self.rowCount)")

        let laidOut = Self.rowCount - skipped
        let reachableRows = Int(3 * Double(Self.viewportSize.height) / Self.rowHeight) + 2
        XCTAssertLessThanOrEqual(
            laidOut, reachableRows,
            "the rows laid out must be proportional to the viewport (\(reachableRows)), not to the list")
    }

    func testEagerStackVirtualizesNothing() async {
        let eagerSnapshot = snapshot(lazyStack: false)
        XCTAssertEqual(
            eagerSnapshot.runtime.virtualizedLayoutSkipCount, 0,
            "a plain VStack keeps its eager behaviour verbatim")
    }

    /// Virtualization is bounded by a scroll viewport. Without one there is
    /// no window to be outside of, and a lazy stack must behave exactly like
    /// an eager one rather than guessing.
    func testLazyStackWithoutAScrollableAncestorLaysEverythingOut() async {
        let unscrolled = WinSwiftUIRendererSnapshotter.snapshot(
            of: LazyVStack(spacing: 0) {
                ForEach(0..<40, id: \.self) { index in
                    Text("row \(index)").frame(width: 200, height: 20)
                }
            },
            size: Self.viewportSize,
            displayScale: 1)
        XCTAssertEqual(
            unscrolled.runtime.virtualizedLayoutSkipCount, 0,
            "no scrollable ancestor means no viewport, and no viewport means no skipping")
    }

    // MARK: - Identical picture

    /// The safety property. Whatever virtualization skips must be invisible:
    /// the lazy tree and the eager tree must rasterize to the same pixels.
    func testVirtualizedListRendersIdenticallyToTheEagerOne() async {
        let lazyPixels = GPUIRawSceneRasterizer.rasterize(
            snapshot(lazyStack: true).scene, size: Self.viewportSize)
        let eagerPixels = GPUIRawSceneRasterizer.rasterize(
            snapshot(lazyStack: false).scene, size: Self.viewportSize)

        let report = comparePixels(lazyPixels, eagerPixels, tolerance: 0)
        XCTAssertEqual(
            report.matchRatio, 1.0,
            "a virtualized list must be pixel-identical to the eager one; first difference at "
                + "\(String(describing: report.firstFailure))")
    }

    /// And it stays identical after scrolling, which is the case that would
    /// catch a row whose subtree was skipped and then never laid out when it
    /// came back into range.
    func testScrolledVirtualizedListStillRendersIdenticallyToTheEagerOne() async {
        let offset = Self.rowHeight * 150

        let lazyRuntime = snapshot(lazyStack: true).runtime
        let eagerRuntime = snapshot(lazyStack: false).runtime
        guard
            let lazyScroll = Self.firstScrollNode(in: lazyRuntime.root),
            let eagerScroll = Self.firstScrollNode(in: eagerRuntime.root)
        else {
            return XCTFail("both trees must contain a scroll container")
        }

        lazyScroll.scrollOffset = offset
        eagerScroll.scrollOffset = offset
        let lazyScene = lazyRuntime.renderScene(at: 1)
        let eagerScene = eagerRuntime.renderScene(at: 1)

        let report = comparePixels(
            GPUIRawSceneRasterizer.rasterize(lazyScene, size: Self.viewportSize),
            GPUIRawSceneRasterizer.rasterize(eagerScene, size: Self.viewportSize),
            tolerance: 0)
        XCTAssertEqual(
            report.matchRatio, 1.0,
            "rows scrolled into view must be laid out before they paint; first difference at "
                + "\(String(describing: report.firstFailure))")
    }

    /// The same property with a plain panel between the scroll view and the
    /// lazy stack — the shape a scroll dirties *around*.
    ///
    /// A scroll marks the scrollable node and its ancestors, never the panel
    /// below it, so that panel takes `layoutSubtree`'s early return. Unless
    /// the pass is told the panel leads to virtualized content it stops
    /// there, the lazy stack is never reached, and rows that scrolled into
    /// range paint at whatever geometry they last had — which, for a row
    /// that was never in range, is nothing at all.
    func testLazyStackBelowAnIntermediatePanelStillResumesRowsOnScroll() async {
        let offset = Self.rowHeight * 150

        let lazyRuntime = Self.nestedSnapshot(lazyStack: true).runtime
        let eagerRuntime = Self.nestedSnapshot(lazyStack: false).runtime
        guard
            let lazyScroll = Self.firstScrollNode(in: lazyRuntime.root),
            let eagerScroll = Self.firstScrollNode(in: eagerRuntime.root)
        else {
            return XCTFail("both trees must contain a scroll container")
        }

        lazyScroll.scrollOffset = offset
        eagerScroll.scrollOffset = offset
        let report = comparePixels(
            GPUIRawSceneRasterizer.rasterize(lazyRuntime.renderScene(at: 1), size: Self.viewportSize),
            GPUIRawSceneRasterizer.rasterize(eagerRuntime.renderScene(at: 1), size: Self.viewportSize),
            tolerance: 0)
        XCTAssertEqual(
            report.matchRatio, 1.0,
            "a lazy stack must stay reachable through a clean intermediate panel; first difference at "
                + "\(String(describing: report.firstFailure))")
    }

    /// The flag that turns a scroll into a layout invalidation is a
    /// statement about the pass that just ran, not a latch. Reconciling the
    /// lazy stack into an eager one must stop charging every later scroll a
    /// layout pass it has no use for.
    func testReconcilingALazyStackIntoAnEagerOneStopsChargingScrollsALayoutPass() async {
        let snapshotted = snapshot(lazyStack: true)
        guard let scroll = Self.firstScrollNode(in: snapshotted.runtime.root),
            let lazyPanel = Self.firstVirtualizingNode(in: snapshotted.runtime.root),
            let stackLayout = lazyPanel.layoutMode.stackLayout
        else {
            return XCTFail("the tree must contain a scroll container and a lazy stack")
        }
        XCTAssertTrue(
            scroll.hasVirtualizedDescendants,
            "a lazy stack that deferred rows must mark its scrollable ancestor")

        // Exactly what reconciliation does when `LazyVStack` becomes
        // `VStack`: the layout mode is reassigned and the pass that follows
        // sees no lazy stack at all.
        lazyPanel.layoutMode = .stack(stackLayout)
        _ = snapshotted.runtime.renderScene(at: 1)

        XCTAssertFalse(
            scroll.hasVirtualizedDescendants,
            "an eager stack defers nothing, so the scrollable ancestor must stop claiming it does")

        scroll.scrollOffset = Self.rowHeight * 20
        XCTAssertFalse(
            scroll.subtreeDirtyFlags.contains(.layout),
            "scrolling over eager content is a paint change; a stale virtualization latch was making "
                + "it a layout pass as well")
    }

    // MARK: - Accessibility over deferred rows

    /// Virtualization defers a row's *subtree*, not the row: the stack still
    /// places every child, so the row rectangle is real and everything
    /// inside it is zero. A projection that walks into it hands a UIA client
    /// a screen rectangle per descendant that is not on the screen.
    func testDeferredRowsProjectRealBoundsRatherThanZeroSizedGhosts() async {
        guard let lazyProjection = AccessibilityProjection.project(runtime: snapshot(lazyStack: true).runtime),
            let eagerProjection = AccessibilityProjection.project(runtime: snapshot(lazyStack: false).runtime)
        else {
            return XCTFail("both trees must project a root element")
        }

        let lazyElements = lazyProjection.flattened()
        let placeholders = lazyElements.filter(\.isVirtualizedPlaceholder)
        XCTAssertGreaterThan(
            placeholders.count, Self.rowCount / 2,
            "every row the viewport cannot reach must project as one flagged placeholder")
        for placeholder in placeholders {
            XCTAssertEqual(
                placeholder.bounds.size.height, Self.rowHeight, accuracy: 0.5,
                "a deferred row keeps the frame its stack placed it at")
            XCTAssertGreaterThan(
                placeholder.bounds.size.width, 0,
                "a deferred row keeps the frame its stack placed it at")
            XCTAssertTrue(
                placeholder.children.isEmpty,
                "nothing inside a deferred row has been laid out, so nothing inside it may be reported")
        }

        // The property that actually protects a client: virtualizing a list
        // must not invent geometry the eager list does not have.
        func zeroSizedCount(_ elements: [AccessibilityElementProjection]) -> Int {
            elements.filter { $0.bounds.size.width <= 0 || $0.bounds.size.height <= 0 }.count
        }
        XCTAssertEqual(
            zeroSizedCount(lazyElements), zeroSizedCount(eagerProjection.flattened()),
            "a virtualized list must project no zero-size elements an eager one does not")
    }

    // MARK: - Visits, not skips

    /// A skip counter says the descent was avoided; it cannot say the walk
    /// was. Visits are the direct measure — one per node `layoutSubtree`
    /// actually descended into — so a list that skipped the descent but
    /// still walked every row is visible here and nowhere else.
    func testLayoutVisitsAtFiveThousandRowsStayProportionalToTheViewport() async {
        let rows = 5000
        let lazyRuntime = Self.plainSnapshot(rowCount: rows, lazyStack: true).runtime
        let eagerRuntime = Self.plainSnapshot(rowCount: rows, lazyStack: false).runtime

        let lazyVisits = lazyRuntime.layoutVisitCount
        let eagerVisits = eagerRuntime.layoutVisitCount
        XCTAssertGreaterThan(
            eagerVisits, rows,
            "an eager \(rows)-row list visits at least one node per row; the probe is wrong if it does not")
        // Measured 2026-08: 38 visits. At offset 0 the 200pt window plus a
        // viewport of overscan on each side reaches rows 0…16 of 24pt rows,
        // about two nodes each, plus the scroll/stack chrome. The bound
        // leaves room for overscan changes and is still two orders of
        // magnitude below the row count.
        XCTAssertLessThan(
            lazyVisits, 200,
            "layout visits must be bounded by the viewport, not the row count; \(lazyVisits) visits "
                + "over \(rows) rows")
        XCTAssertLessThan(
            lazyVisits * 10, eagerVisits,
            "virtualization must remove an order of magnitude of recursive layout work, not a constant "
                + "factor; lazy \(lazyVisits) vs eager \(eagerVisits)")
    }

    // MARK: - What deferral costs

    /// Deferral is invisible only to rows that observe nothing.
    /// `onLayout` is published by the layout pass, so a row outside the
    /// overscan stops reporting until it comes back into range.
    ///
    /// This is the semantic that keeps `List` out of `.lazyStack` for now
    /// (see `docs/GPURenderingPipeline.md`, "Why `List` is not virtualized
    /// yet"): `List` mirrors every row's frame through `onLayout` because
    /// `resolvedFrame` is internal to the runtime, and its arrow-key
    /// scroll-into-view reads that mirror — so the rows it would most need
    /// to scroll to are exactly the ones deferral would leave unmeasured.
    func testALazyStackPublishesLayoutOnlyForRowsWithinRange() async {
        let snapshotted = snapshot(lazyStack: true)
        guard let scroll = Self.firstScrollNode(in: snapshotted.runtime.root),
            let lazyPanel = Self.firstVirtualizingNode(in: snapshotted.runtime.root),
            lazyPanel.children.count == Self.rowCount
        else {
            return XCTFail("the tree must contain a scroll container and a lazy stack of every row")
        }

        let reports = LayoutReportLog()
        for (index, row) in lazyPanel.children.enumerated() {
            row.onLayout = { _ in reports.indices.insert(index) }
        }

        let targetRow = 150
        scroll.scrollOffset = Self.rowHeight * Double(targetRow)
        _ = snapshotted.runtime.renderScene(at: 1)

        XCTAssertTrue(
            reports.indices.contains(targetRow),
            "a row scrolled into range is laid out, and laying it out publishes its frame")
        XCTAssertFalse(
            reports.indices.contains(0),
            "a row scrolled out of range is not laid out, so it publishes nothing")
        XCTAssertFalse(
            reports.indices.contains(Self.rowCount - 1),
            "a row that was never in range has never published a frame at all")
    }

    @MainActor
    private final class LayoutReportLog {
        var indices: Set<Int> = []
    }

    private static func firstScrollNode(in node: ViewNode) -> ViewNode? {
        if node.scrollAxis != nil { return node }
        for child in node.children {
            if let found = firstScrollNode(in: child) { return found }
        }
        return nil
    }

    // MARK: - Probes

    private struct PlainRows: View {
        let count: Int
        let lazyStack: Bool

        var body: some View {
            ScrollView {
                if lazyStack {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<count, id: \.self) { index in
                            Text("row \(index)").frame(width: 220, height: LazyStackVirtualizationTests.rowHeight)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(0..<count, id: \.self) { index in
                            Text("row \(index)").frame(width: 220, height: LazyStackVirtualizationTests.rowHeight)
                        }
                    }
                }
            }
        }
    }

    private struct NestedRows: View {
        let count: Int
        let lazyStack: Bool

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    if lazyStack {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<count, id: \.self) { index in
                                Text("row \(index)")
                                    .frame(width: 220, height: LazyStackVirtualizationTests.rowHeight)
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(0..<count, id: \.self) { index in
                                Text("row \(index)")
                                    .frame(width: 220, height: LazyStackVirtualizationTests.rowHeight)
                            }
                        }
                    }
                }
            }
        }
    }

    private static func plainSnapshot(rowCount: Int, lazyStack: Bool) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: PlainRows(count: rowCount, lazyStack: lazyStack),
            size: viewportSize,
            displayScale: 1)
    }

    private static func nestedSnapshot(lazyStack: Bool) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: NestedRows(count: rowCount, lazyStack: lazyStack),
            size: viewportSize,
            displayScale: 1)
    }

    // MARK: - The viewport window itself

    func testVirtualizationWindowIsInLocalSpaceAndFollowsTheScrollOffset() async {
        let snapshotted = snapshot(lazyStack: true)
        guard let scroll = Self.firstScrollNode(in: snapshotted.runtime.root),
            let lazyPanel = Self.firstVirtualizingNode(in: snapshotted.runtime.root)
        else {
            return XCTFail("the tree must contain a scroll container and a lazy stack")
        }

        let initial = lazyPanel.layoutVirtualizationWindow()
        XCTAssertNotNil(initial, "a scrollable ancestor must produce a virtualization window")
        XCTAssertEqual(initial?.size.height ?? 0, Double(Self.viewportSize.height), accuracy: 0.5)

        scroll.scrollOffset = Self.rowHeight * 100
        _ = snapshotted.runtime.renderScene(at: 1)
        let scrolled = lazyPanel.layoutVirtualizationWindow()
        XCTAssertGreaterThan(
            scrolled?.origin.y ?? 0, initial?.origin.y ?? 0,
            "the window must follow the resolved scroll offset, or rows that scroll into view never "
                + "get laid out")
    }

    /// A plain stack never virtualizes, whatever is above it.
    func testEagerStackHasNoVirtualizationWindow() async {
        let eager = snapshot(lazyStack: false)
        XCTAssertNil(Self.firstVirtualizingNode(in: eager.runtime.root))
    }

    private static func firstVirtualizingNode(in node: ViewNode) -> ViewNode? {
        if node.layoutMode.virtualizesChildren { return node }
        for child in node.children {
            if let found = firstVirtualizingNode(in: child) { return found }
        }
        return nil
    }
}
