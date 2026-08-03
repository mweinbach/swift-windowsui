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

    private static func firstScrollNode(in node: ViewNode) -> ViewNode? {
        if node.scrollAxis != nil { return node }
        for child in node.children {
            if let found = firstScrollNode(in: child) { return found }
        }
        return nil
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
