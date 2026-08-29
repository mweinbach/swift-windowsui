import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Data Lists keep logical metadata for every element and construct only a
/// bounded viewport. Static rows remain an independent eager reference for
/// layout/pixels and for the historical standalone physical-row behavior.
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

    private func makeManagedRuntime<V: View>(
        _ view: V, size: IntSize = ListVirtualizationTests.viewport
    ) -> MountedLazyListTestHost {
        MountedLazyListTestHost(size: Size(width: Double(size.width), height: Double(size.height))) {
            view.frame(width: Double(size.width), height: Double(size.height))
        }
    }

    private func row(_ index: Int, height: Double = 24) -> some View {
        Text("ROW \(index)")
            .frame(width: 220, height: height)
            .accessibilityIdentifier("virtual-row-\(index)")
    }

    private func plainList(rowCount: Int) -> some View {
        List(0..<rowCount, id: \.self) { index in self.row(index) }
    }

    private func staticList(
        rowCount: Int, height: Double = 24, selection: Binding<Int?>? = nil
    ) -> some View {
        // Prebuilt array contents contain no ForEach/deferred data segment.
        let rows = (0..<rowCount).map { AnyView(row($0, height: height).tag($0)) }
        return List(selection: selection) { rows }
    }

    @discardableResult
    private func settle(
        _ host: MountedLazyListTestHost, file: StaticString = #filePath, line: UInt = #line
    ) throws -> GPUIScene {
        for _ in 0..<16 {
            let scene = host.runtime.renderScene(at: 1)
            if !host.runtime.isDirty { return scene }
        }
        return try XCTUnwrap(
            nil as GPUIScene?, "Expected ordinary bounded List work to settle within 16 renders", file: file, line: line
        )
    }

    private func logicalItem(
        for identifier: Int, in host: MountedLazyListTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> RetainedLazyListAccessibilityItem {
        let list = try host.list(file: file, line: line)
        let source = try XCTUnwrap(DeferredListScrollSource.attached(to: list), file: file, line: line)
        let witness = try XCTUnwrap(host.runtime.captureLazyListScrollSource(in: list), file: file, line: line)
        let ordinal = try XCTUnwrap(
            source.index(
                for: AnyHashable(identifier),
                isCurrent: {
                    DeferredListScrollSource.attached(to: list) === source
                        && host.runtime.isLazyListScrollSourceCurrent(witness, in: list)
                }), file: file, line: line)
        let metadata = try XCTUnwrap(source.row(at: ordinal), file: file, line: line)
        return try XCTUnwrap(
            host.runtime.lazyListTarget(in: list, key: metadata.providerKey), file: file, line: line)
    }

    private func realizedRow(
        for identifier: Int, item: RetainedLazyListAccessibilityItem, in host: MountedLazyListTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        for _ in 0..<16 {
            switch host.runtime.resolveLazyListTarget(item) {
            case .ready(let roots):
                // A logical record emits real gap and row leaves. A gap is
                // never the authored target for scrolling or accessibility.
                return try XCTUnwrap(
                    roots.flatMap { MountedLazyListTestHost.descendants(in: $0) }.first {
                        $0.accessibilityIdentifier == "virtual-row-\(identifier)"
                    }, file: file, line: line)
            case .pending:
                _ = host.runtime.renderScene(at: 1)
            case .empty, .obsolete, .unsupported:
                return try XCTUnwrap(
                    nil as ViewNode?, "Expected a current nonempty authored row", file: file, line: line)
            }
        }
        return try XCTUnwrap(nil as ViewNode?, "Logical target did not settle", file: file, line: line)
    }

    func testSmallListsKeepTheirExistingEagerStackContract() async {
        let small = makeRuntime(staticList(rowCount: 64))

        XCTAssertFalse(small.node.layoutMode.virtualizesChildren)
        XCTAssertEqual(small.runtime.virtualizedLayoutSkipCount, 0)
        XCTAssertFalse(
            MountedLazyListTestHost.descendants(in: small.node).contains { $0.retainedLazyListAdapter != nil })

        var selection: Int? = 0
        let binding = Binding<Int?>(get: { selection }, set: { selection = $0 })
        weak var releasedRuntime: RetainedViewRuntime?
        let standaloneList: ViewNode = {
            let result = makeRuntime(
                staticList(rowCount: 5, height: 40, selection: binding),
                size: IntSize(width: 260, height: 100)
            )
            releasedRuntime = result.runtime
            return result.node
        }()

        XCTAssertNil(releasedRuntime, "row interaction state must never retain its runtime in a reference cycle")
        let selectableRows = standaloneList.children.filter {
            $0.accessibilityTraits.contains(.isSelectable)
        }
        XCTAssertEqual(selectableRows.count, 5)
        for row in selectableRows.dropLast() {
            row.onKeyDown?(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
        }
        XCTAssertEqual(selection, 4)
        XCTAssertGreaterThan(
            standaloneList.scrollOffset, 0,
            "an already-laid-out static List must reveal keyboard selection after its runtime is released"
        )
    }

    func testListsAboveThresholdUseViewportBoundedLayout() async throws {
        let large = makeManagedRuntime(plainList(rowCount: 100))
        defer { large.close() }
        try settle(large)
        let list = try large.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)

        XCTAssertTrue(list.layoutMode.virtualizesChildren)
        XCTAssertTrue(try large.scrollContainer().hasVirtualizedDescendants)
        XCTAssertEqual(adapter.logicalRecordCount, 100)
        XCTAssertGreaterThan(adapter.mountedRecordCount, 0)
        XCTAssertLessThan(adapter.mountedRecordCount, 32)
        XCTAssertNil(large.find("virtual-row-99"), "An unbuilt logical record must not have a placeholder ViewNode")
    }

    func testThousandRowListLayoutVisitsStayProportionalToViewport() async throws {
        let large = makeManagedRuntime(plainList(rowCount: 1_000))
        defer { large.close() }
        try settle(large)
        let adapter = try XCTUnwrap(try large.list().retainedLazyListAdapter)

        XCTAssertEqual(adapter.logicalRecordCount, 1_000)
        XCTAssertLessThan(adapter.mountedRecordCount, 32)
        XCTAssertGreaterThan(large.runtime.maxLayoutVisitsInAnyPass, 0)
        XCTAssertLessThan(
            large.runtime.maxLayoutVisitsInAnyPass, 240,
            "recursive layout visits must follow the visible rows, not the 1000-row collection"
        )
        XCTAssertNil(large.find("virtual-row-900"))
    }

    func testFiftyThousandRowsBuildNoFactoriesAtInitializationAndOnlyABoundedViewport() async throws {
        var factoryCalls = 0
        let view = List(0..<50_000, id: \.self) { index in
            let _ = { factoryCalls += 1 }()
            self.row(index)
        }
        XCTAssertEqual(factoryCalls, 0, "Data initialization must only describe logical records")
        let large = makeManagedRuntime(view)
        defer { large.close() }
        XCTAssertEqual(factoryCalls, 0, "Constructing the List descriptor must not invoke row factories")

        try settle(large)

        XCTAssertGreaterThan(factoryCalls, 0)
        XCTAssertLessThan(factoryCalls, 128, "First viewport construction must be independent of data count")
        let adapter = try XCTUnwrap(try large.list().retainedLazyListAdapter)
        XCTAssertEqual(adapter.logicalRecordCount, 50_000)
        XCTAssertLessThan(adapter.mountedRecordCount, 32)
        XCTAssertNil(large.find("virtual-row-49999"))
    }

    func testVirtualizedListRemainsPixelIdenticalToItsEagerLayout() async throws {
        // Unknown extents may change scrollbar thumb geometry. Both fixtures
        // explicitly hide indicators so this exact oracle compares row/chrome
        // rendering independently of the logical extent estimate.
        let lazy = makeManagedRuntime(plainList(rowCount: 120).scrollIndicators(.hidden))
        defer { lazy.close() }
        let eager = makeRuntime(staticList(rowCount: 120).scrollIndicators(.hidden))
        XCTAssertFalse(
            MountedLazyListTestHost.descendants(in: eager.node).contains { $0.retainedLazyListAdapter != nil })
        let stackLayout = try XCTUnwrap(eager.node.layoutMode.stackLayout)
        eager.node.layoutMode = .stack(stackLayout)

        let initialLazy = try settle(lazy)
        let initialEager = eager.runtime.renderScene(at: 1)
        let initial = comparePixels(
            GPUIRawSceneRasterizer.rasterize(initialLazy, size: Self.viewport),
            GPUIRawSceneRasterizer.rasterize(initialEager, size: Self.viewport),
            tolerance: 0
        )
        XCTAssertEqual(initial.matchRatio, 1, "virtualizing a List must not change its visible pixels")

        let item = try logicalItem(for: 40, in: lazy)
        defer { lazy.runtime.releaseLazyListTarget(item) }
        let lazyRow = try realizedRow(for: 40, item: item, in: lazy)
        let eagerRow = try XCTUnwrap(
            MountedLazyListTestHost.descendants(in: eager.node).first { $0.accessibilityIdentifier == "virtual-row-40" }
        )
        XCTAssertTrue(lazy.runtime.scrollToDescendant(lazyRow, anchorY: 0, transaction: Transaction()))
        XCTAssertTrue(eager.runtime.scrollToDescendant(eagerRow, anchorY: 0, transaction: Transaction()))
        let scrolledLazy = try settle(lazy)
        let scrolledEager = eager.runtime.renderScene(at: 1)

        // Align the same authored row, not arbitrary offsets through unknown
        // offscreen heights. Its frame relative to the viewport must agree.
        let lazyFrame = try XCTUnwrap(lazy.runtime.resolvedLayoutFrame(of: lazyRow))
        let lazyViewport = try XCTUnwrap(lazy.runtime.resolvedLayoutFrame(of: try lazy.scrollContainer()))
        let eagerFrame = try XCTUnwrap(eager.runtime.resolvedLayoutFrame(of: eagerRow))
        let eagerViewport = try XCTUnwrap(eager.runtime.resolvedLayoutFrame(of: eager.node))
        XCTAssertEqual(
            lazyFrame.origin.y - lazyViewport.origin.y, eagerFrame.origin.y - eagerViewport.origin.y, accuracy: 0)
        XCTAssertEqual(lazyFrame.size, eagerFrame.size)
        let scrolled = comparePixels(
            GPUIRawSceneRasterizer.rasterize(scrolledLazy, size: Self.viewport),
            GPUIRawSceneRasterizer.rasterize(scrolledEager, size: Self.viewport),
            tolerance: 0
        )
        XCTAssertEqual(scrolled.matchRatio, 1, "rows entering the viewport must render exactly like eager rows")
    }

    func testKeyboardSelectionCanRevealADeferredFarAwayRow() async throws {
        var selection: Int? = 0
        let binding = Binding<Int?>(get: { selection }, set: { selection = $0 })
        let result = makeManagedRuntime(
            List(0..<1_000, id: \.self, selection: binding) { index in self.row(index) }
        )
        defer { result.close() }
        try settle(result)
        let source = try result.rowRoot("virtual-row-0")
        let sourceKeyDown = try XCTUnwrap(source.onKeyDown)
        XCTAssertNil(result.find("virtual-row-900"))
        XCTAssertNil(result.find("virtual-row-899"))

        // Source 0 is the real attached handler. Selection metadata, not an
        // imaginary mounted row 899, selects the distant next logical record.
        selection = 899
        sourceKeyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))

        XCTAssertEqual(selection, 900)
        let target = try result.rowRoot("virtual-row-900")
        XCTAssertGreaterThan(try result.scrollContainer().scrollOffset, 20_000)
        XCTAssertTrue(result.runtime.focusedNode === target, "A supported distant navigation must focus immediately")
        XCTAssertFalse(target.isLayoutDeferredByVirtualization)

        let targetKeyDown = try XCTUnwrap(target.onKeyDown)
        targetKeyDown(KeyboardEvent(keyCode: KeyboardKey.upArrow.rawValue))
        XCTAssertEqual(selection, 899)
        let previous = try result.rowRoot("virtual-row-899")
        XCTAssertTrue(result.runtime.focusedNode === previous)
        XCTAssertFalse(previous.isLayoutDeferredByVirtualization)
        try settle(result)
    }

    func testScrollViewReaderReachesDeferredRowsInLongLists() async throws {
        var proxy: ScrollViewProxy?
        let result = makeManagedRuntime(
            ScrollViewReader { capturedProxy in
                proxy = capturedProxy
                List(0..<200, id: \.self) { index in self.row(index).id("row-\(index)") }
            }
        )
        defer { result.close() }
        try settle(result)
        let scroll = try result.scrollContainer()
        XCTAssertEqual(try XCTUnwrap(try result.list().retainedLazyListAdapter).logicalRecordCount, 200)
        XCTAssertNil(result.find("virtual-row-175"))

        try XCTUnwrap(proxy).scrollTo("row-175", anchor: .top)
        try settle(result)
        XCTAssertGreaterThan(scroll.scrollOffset, 3_000)
        XCTAssertFalse(try XCTUnwrap(result.find("virtual-row-175")).isLayoutDeferredByVirtualization)

        try XCTUnwrap(proxy).scrollTo("row-0", anchor: .top)
        try settle(result)
        XCTAssertEqual(scroll.scrollOffset, 0, accuracy: 0.5)
        XCTAssertNotNil(result.find("virtual-row-0"))
    }

    func testDeferredListRowsExposeLogicalAccessibilityWithoutFakeGeometry() async throws {
        var factoryCalls = 0
        let result = makeManagedRuntime(
            List(0..<100, id: \.self) { index in
                let _ = { factoryCalls += 1 }()
                self.row(index)
            }
        )
        defer { result.close() }
        try settle(result)
        let list = try result.list()
        let beforeEnumeration = factoryCalls
        let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: result.runtime))
        XCTAssertTrue(projection.flattened().filter(\.isVirtualizedPlaceholder).isEmpty)
        var items: [RetainedLazyListAccessibilityItem] = []
        var previous: RetainedLazyListAccessibilityItem?
        for _ in 0..<100 {
            let item = try XCTUnwrap(result.runtime.lazyListAccessibilityItem(in: list, after: previous))
            items.append(item)
            previous = item
        }
        XCTAssertNil(result.runtime.lazyListAccessibilityItem(in: list, after: previous))
        XCTAssertEqual(items.count, 100)
        XCTAssertEqual(factoryCalls, beforeEnumeration, "Logical enumeration must not realize a row")
        XCTAssertNil(items[90].knownLeafCount, "An unbuilt logical row has unknown structure, not synthetic geometry")
        XCTAssertNil(result.runtime.realizedLazyListAccessibilityNodes(for: items[90]))
        XCTAssertNil(result.find("virtual-row-90"))
        XCTAssertFalse(result.runtime.isDirty)
    }

    func testScrollDisabledLongListPreservesVirtualizationAndProgrammaticAccess() async throws {
        var proxy: ScrollViewProxy?
        let disabled = makeManagedRuntime(
            ScrollViewReader { capturedProxy in
                proxy = capturedProxy
                List(0..<100, id: \.self) { index in self.row(index).id("row-\(index)") }
                    .scrollDisabled(true)
            }
        )
        defer { disabled.close() }
        try settle(disabled)
        let scroll = try disabled.scrollContainer()
        let adapter = try XCTUnwrap(try disabled.list().retainedLazyListAdapter)

        XCTAssertEqual(scroll.scrollAxis, .vertical)
        XCTAssertFalse(scroll.isScrollInputEnabled)
        XCTAssertTrue(try disabled.list().layoutMode.virtualizesChildren)
        XCTAssertEqual(adapter.logicalRecordCount, 100)
        XCTAssertLessThan(adapter.mountedRecordCount, 32)
        XCTAssertNil(disabled.find("virtual-row-95"))

        disabled.runtime.mouseWheel(at: Point(x: 130, y: 100), delta: -1)
        try settle(disabled)
        XCTAssertEqual(scroll.scrollOffset, 0)

        try XCTUnwrap(proxy).scrollTo("row-95", anchor: .top)
        try settle(disabled)
        let programmaticOffset = scroll.scrollOffset
        XCTAssertGreaterThan(programmaticOffset, 2_000)
        let distantRow = try XCTUnwrap(disabled.find("virtual-row-95"))
        XCTAssertFalse(distantRow.isLayoutDeferredByVirtualization)
        XCTAssertLessThan(adapter.mountedRecordCount, 32)

        disabled.runtime.mouseWheel(at: Point(x: 130, y: 100), delta: 1)
        try settle(disabled)
        XCTAssertEqual(scroll.scrollOffset, programmaticOffset)
        XCTAssertEqual(scroll.resolvedScrollOffset, programmaticOffset)
    }
}
