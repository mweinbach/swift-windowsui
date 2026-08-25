import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// `List` now shares the existing lazy-stack layout path once its row count
/// warrants virtualization. Nodes are still constructed eagerly; the bounded
/// work here is recursive layout, and placed offscreen rows stay reachable to
/// keyboard selection, ScrollViewReader, and accessibility realization.
@MainActor
final class ListVirtualizationTests: XCTestCase {
    private static let viewport = IntSize(width: 260, height: 200)

    private func makeRuntime<V: View>(
        _ view: V,
        size: IntSize = ListVirtualizationTests.viewport
    ) -> (runtime: RetainedViewRuntime, node: ViewNode) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let logicalSize = Size(width: Double(size.width), height: Double(size.height))
        let context = ViewBuildContext(canvasSizeProvider: { logicalSize }, invalidateHandler: {})
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        node.frame = Rect(origin: .zero, size: logicalSize)
        runtime.root.addChild(node)
        runtime.setRootSize(size)
        _ = runtime.renderScene(at: 1)
        return (runtime, node)
    }

    private func plainList(rowCount: Int) -> some View {
        List(0..<rowCount, id: \.self) { index in
            Text("ROW \(index)")
                .frame(width: 220, height: 24)
        }
    }

    func testSmallListsKeepTheirExistingEagerStackContract() async {
        let small = makeRuntime(plainList(rowCount: 64))

        XCTAssertFalse(small.node.layoutMode.virtualizesChildren)
        XCTAssertEqual(small.runtime.virtualizedLayoutSkipCount, 0)
    }

    func testListsAboveThresholdUseViewportBoundedLayout() async {
        let large = makeRuntime(plainList(rowCount: 100))

        XCTAssertTrue(large.node.layoutMode.virtualizesChildren)
        XCTAssertTrue(large.node.hasVirtualizedDescendants)
        XCTAssertGreaterThan(large.runtime.virtualizedLayoutSkipCount, 80)
        XCTAssertTrue(large.node.children.contains { $0.isLayoutDeferredByVirtualization })
    }

    func testThousandRowListLayoutVisitsStayProportionalToViewport() async {
        let large = makeRuntime(plainList(rowCount: 1000))

        XCTAssertTrue(large.node.layoutMode.virtualizesChildren)
        XCTAssertGreaterThan(large.runtime.virtualizedLayoutSkipCount, 900)
        XCTAssertGreaterThan(large.runtime.maxLayoutVisitsInAnyPass, 0)
        XCTAssertLessThan(
            large.runtime.maxLayoutVisitsInAnyPass,
            240,
            "recursive layout visits must follow the visible rows, not the 1000-row collection"
        )
    }

    func testVirtualizedListRemainsPixelIdenticalToItsEagerLayout() async throws {
        let lazy = makeRuntime(plainList(rowCount: 120))
        let eager = makeRuntime(plainList(rowCount: 120))
        let stackLayout = try XCTUnwrap(eager.node.layoutMode.stackLayout)
        eager.node.layoutMode = .stack(stackLayout)

        let initialLazy = lazy.runtime.renderScene(at: 1)
        let initialEager = eager.runtime.renderScene(at: 1)
        let initial = comparePixels(
            GPUIRawSceneRasterizer.rasterize(initialLazy, size: Self.viewport),
            GPUIRawSceneRasterizer.rasterize(initialEager, size: Self.viewport),
            tolerance: 0
        )
        XCTAssertEqual(initial.matchRatio, 1, "virtualizing a List must not change its visible pixels")

        lazy.node.scrollOffset = 1200
        eager.node.scrollOffset = 1200
        let scrolled = comparePixels(
            GPUIRawSceneRasterizer.rasterize(lazy.runtime.renderScene(at: 1), size: Self.viewport),
            GPUIRawSceneRasterizer.rasterize(eager.runtime.renderScene(at: 1), size: Self.viewport),
            tolerance: 0
        )
        XCTAssertEqual(scrolled.matchRatio, 1, "rows entering the viewport must render exactly like eager rows")
    }

    func testKeyboardSelectionCanRevealADeferredFarAwayRow() async throws {
        var selection: Int? = 0
        let binding = Binding<Int?>(get: { selection }, set: { selection = $0 })
        let result = makeRuntime(
            List(0..<1000, id: \.self, selection: binding) { index in
                Text("ROW \(index)")
                    .frame(width: 220, height: 24)
            }
        )
        let selectableRows = result.node.children.filter {
            $0.accessibilityTraits.contains(.isSelectable)
        }
        XCTAssertEqual(selectableRows.count, 1000)

        let target = try XCTUnwrap(selectableRows.dropFirst(900).first)
        XCTAssertTrue(target.isLayoutDeferredByVirtualization)

        selection = 899
        selectableRows[899].onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))

        XCTAssertEqual(selection, 900)
        XCTAssertGreaterThan(result.node.scrollOffset, 20_000)
        XCTAssertTrue(result.runtime.focusedNode === target)

        _ = result.runtime.renderScene(at: 1)
        XCTAssertFalse(target.isLayoutDeferredByVirtualization)

        target.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
        XCTAssertEqual(selection, 899)
        XCTAssertTrue(result.runtime.focusedNode === selectableRows[899])
    }

    func testScrollViewReaderReachesDeferredRowsInLongLists() async {
        var proxy: ScrollViewProxy?
        let result = makeRuntime(
            ScrollViewReader { capturedProxy in
                proxy = capturedProxy
                List(0..<200, id: \.self) { index in
                    Text("ROW \(index)")
                        .frame(width: 220, height: 24)
                        .id("row-\(index)")
                }
            }
        )

        XCTAssertTrue(result.node.layoutMode.virtualizesChildren)

        proxy?.scrollTo("row-175", anchor: .top)
        XCTAssertGreaterThan(result.node.scrollOffset, 3000)

        _ = result.runtime.renderScene(at: 1)
        proxy?.scrollTo("row-0", anchor: .top)
        XCTAssertEqual(result.node.scrollOffset, 0, accuracy: 0.5)
    }

    func testDeferredListRowsProjectAccessibilityPlaceholders() async throws {
        let result = makeRuntime(plainList(rowCount: 100))
        let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: result.runtime))
        let placeholders = projection.flattened().filter(\.isVirtualizedPlaceholder)

        XCTAssertGreaterThan(placeholders.count, 75)
        XCTAssertTrue(placeholders.allSatisfy { $0.bounds.size.height > 0 })
        XCTAssertTrue(placeholders.allSatisfy { $0.children.isEmpty })
    }

    func testScrollDisabledLongListKeepsEagerLayout() async {
        let disabled = makeRuntime(plainList(rowCount: 100).scrollDisabled(true))

        XCTAssertNil(disabled.node.scrollAxis)
        XCTAssertFalse(disabled.node.layoutMode.virtualizesChildren)
        XCTAssertEqual(disabled.runtime.virtualizedLayoutSkipCount, 0)
    }
}
