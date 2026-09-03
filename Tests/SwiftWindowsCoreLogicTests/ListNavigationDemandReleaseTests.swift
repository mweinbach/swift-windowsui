import SwiftWindowsCore
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI

/// Small raw-runtime cases isolate native demand cleanup from public List
/// construction. The unchanged public warm-navigation test owns that coverage.
@MainActor
final class ListNavigationDemandReleaseTests: XCTestCase {
    func testOriginalQueuedRevealSurvivesItsNativeDemandRelease() async throws {
        let fixture = try DemandReleaseFixture()
        defer { fixture.close() }
        let (item, receipt, target) = try fixture.prepareQueuedReveal()
        let geometry = try XCTUnwrap(receipt.geometryRevision)
        let pass = fixture.runtime.layoutPassID
        let factories = fixture.events.factories

        fixture.runtime.releaseLazyListTarget(item, afterNavigation: receipt)

        XCTAssertEqual(fixture.runtime.layoutPassID, pass)
        XCTAssertEqual(fixture.events.factories, factories)
        XCTAssertEqual(receipt.geometryRevision, geometry + 1)
        XCTAssertTrue(fixture.runtime.isListNavigationGeometryCurrent(receipt))
        XCTAssertTrue(receipt.permitsReveal(in: fixture.runtime, target: target))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertEqual(fixture.events.focusEntries, [4])
        // A consumed demand cannot create another invalidation or refresh.
        fixture.runtime.releaseLazyListTarget(item, afterNavigation: receipt)
        XCTAssertEqual(receipt.geometryRevision, geometry + 1)
        XCTAssertTrue(fixture.runtime.isListNavigationGeometryCurrent(receipt))
        XCTAssertEqual(fixture.runtime.layoutPassID, pass)

        _ = fixture.runtime.renderFrame(at: 0)

        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0)
        XCTAssertTrue(fixture.runtime.focusedNode === target)
        XCTAssertTrue(target.parent === fixture.list)
        XCTAssertEqual(fixture.events.focusEntries, [4])
        XCTAssertLessThan(target.resolvedFrame.minY - fixture.scroll.scrollOffset, fixture.scroll.resolvedFrame.height)
        XCTAssertGreaterThan(target.resolvedFrame.maxY - fixture.scroll.scrollOffset, 0)
        let acceptedOffset = fixture.scroll.scrollOffset
        _ = fixture.runtime.renderFrame(at: 0)
        XCTAssertEqual(fixture.scroll.scrollOffset, acceptedOffset)
        XCTAssertEqual(fixture.events.focusEntries, [4])
        XCTAssertFalse(receipt.finishNavigation(), "The queued reveal cannot repeat navigation")
    }

    func testSameValueAuthoredScrollCannotBeAcknowledgedAsDemandCleanup() async throws {
        let fixture = try DemandReleaseFixture()
        defer { fixture.close() }
        let (item, receipt, target) = try fixture.prepareQueuedReveal()
        let geometry = receipt.geometryRevision
        XCTAssertTrue(fixture.scroll.hasVirtualizedDescendants)
        let offset = fixture.scroll.scrollOffset

        fixture.scroll.scrollOffset = offset

        XCTAssertEqual(fixture.scroll.scrollOffset, offset)
        XCTAssertFalse(fixture.runtime.isListNavigationGeometryCurrent(receipt))
        XCTAssertFalse(receipt.permitsReveal(in: fixture.runtime, target: target))
        let pass = fixture.runtime.layoutPassID
        let factories = fixture.events.factories
        fixture.runtime.releaseLazyListTarget(item, afterNavigation: receipt)
        XCTAssertEqual(receipt.geometryRevision, geometry)
        XCTAssertFalse(fixture.runtime.isListNavigationGeometryCurrent(receipt))
        XCTAssertEqual(fixture.runtime.layoutPassID, pass)
        XCTAssertEqual(fixture.events.factories, factories)

        _ = fixture.runtime.renderFrame(at: 0)
        _ = fixture.runtime.renderFrame(at: 0)

        XCTAssertEqual(fixture.scroll.scrollOffset, offset)
        XCTAssertTrue(fixture.runtime.focusedNode === target)
        XCTAssertTrue(target.parent === fixture.list)
        XCTAssertEqual(fixture.events.focusEntries, [4])
        XCTAssertFalse(receipt.finishNavigation())
    }

    func testNewFocusOrReplacementCannotBorrowOriginalCleanupGeometry() async throws {
        for replaceTarget in [false, true] {
            let fixture = try DemandReleaseFixture()
            defer { fixture.close() }
            let (item, receipt, target) = try fixture.prepareQueuedReveal()
            let geometry = receipt.geometryRevision
            let source = try fixture.row(0)
            if replaceTarget {
                let replacement = ViewNode(
                    preferredSize: target.preferredSize, isFocusable: true, accessibilityTraits: .isSelectable)
                replacement.retainedViewIdentity = target.retainedViewIdentity
                replacement.dynamicContentIndex = 4
                replacement.interceptsVerticalArrowKeys = true
                _ = fixture.scope.makeRowOwner(on: replacement)
                let children = fixture.list.children
                target.removeFromParent()
                fixture.list.setChildren(children.map { $0 === target ? replacement : $0 })
                XCTAssertNil(target.parent)
            } else {
                fixture.runtime.requestFocus(source)
                XCTAssertTrue(fixture.runtime.focusedNode === source)
            }
            XCTAssertFalse(receipt.permitsReveal(in: fixture.runtime, target: target))
            let pass = fixture.runtime.layoutPassID
            let factories = fixture.events.factories

            fixture.runtime.releaseLazyListTarget(item, afterNavigation: receipt)

            XCTAssertEqual(receipt.geometryRevision, geometry)
            XCTAssertEqual(fixture.runtime.layoutPassID, pass)
            XCTAssertEqual(fixture.events.factories, factories)
            XCTAssertFalse(receipt.permitsReveal(in: fixture.runtime, target: target))
            _ = fixture.runtime.renderFrame(at: 0)
            _ = fixture.runtime.renderFrame(at: 0)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertFalse(fixture.runtime.focusedNode === target)
            if !replaceTarget { XCTAssertTrue(fixture.runtime.focusedNode === source) }
            XCTAssertEqual(fixture.events.focusEntries.filter { $0 == 4 }, [4])
            XCTAssertFalse(receipt.finishNavigation())
        }
    }
}

@MainActor
private final class DemandReleaseFixture {
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let list: ViewNode
    let scroll: ViewNode
    let runtime: RetainedViewRuntime
    let scope: RetainedListNavigationOwner
    let events: DemandReleaseEvents

    init() throws {
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
        let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
        list.retainedViewIdentity = identity
        list.retainedSubtreeBuildLease = DemandReleaseLease()
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 60), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical, children: [list])
        let runtime = RetainedViewRuntime(root: scroll)
        let scope = RetainedListNavigationOwner(runtime: runtime)
        scope.install(on: scroll)
        let events = DemandReleaseEvents()
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            source.replaceData(Array(0..<16), id: \.self, identityRoot: identity) { value, prefix in
                events.factories.append(value)
                let row = ViewNode(
                    preferredSize: Size(width: 120, height: 20), isFocusable: true,
                    accessibilityTraits: .isSelectable)
                row.retainedViewIdentity = prefix.appending(.slot(0)).appending(.role(.row))
                row.dynamicContentIndex = value
                row.interceptsVerticalArrowKeys = true
                row.onFocusEnter = { events.focusEntries.append(value) }
                _ = scope.makeRowOwner(on: row)
                return [row]
            })
        list.retainedLazyListAdapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 100,
                maximumMountedRecords: 16, maximumMountedLeaves: 16, maximumProtectedRecords: 2))
        runtime.clock = { 0 }
        self.source = source
        self.list = list
        self.scroll = scroll
        self.runtime = runtime
        self.scope = scope
        self.events = events
        for _ in 0..<4 {
            _ = runtime.renderFrame(at: 0)
            if !runtime.isDirty { break }
        }
        XCTAssertFalse(runtime.isDirty)
        XCTAssertTrue(scroll.hasVirtualizedDescendants)
        let target = try row(4)
        XCTAssertFalse(target.isLayoutDeferredByVirtualization)
        XCTAssertGreaterThan(target.resolvedFrame.minY, scroll.resolvedFrame.height)
    }

    func row(_ value: Int) throws -> ViewNode {
        try XCTUnwrap(list.children.first { $0.dynamicContentIndex == value })
    }

    func prepareQueuedReveal() throws -> (
        RetainedLazyListAccessibilityItem, RetainedListNavigationReceipt, ViewNode
    ) {
        let target = try row(4)
        let token = try XCTUnwrap(source.token(for: .init(4)))
        let item = try XCTUnwrap(runtime.lazyListTarget(in: list, token: token))
        let receipt = try XCTUnwrap(scope.prepareAction(from: try XCTUnwrap(try row(0).listNavigationOwner)))
        guard case .ready(let roots) = runtime.resolveLazyListTarget(item), roots.contains(where: { $0 === target })
        else {
            XCTFail("The original warm target must acquire its own native demand")
            throw DemandReleaseFixtureError.unready
        }
        XCTAssertTrue(receipt.prepareTarget(try XCTUnwrap(target.listNavigationOwner)))
        XCTAssertFalse(receipt.finishNavigation(), "Pending render flags must queue the warm reveal")
        XCTAssertTrue(runtime.focusedNode === target)
        XCTAssertTrue(receipt.permitsReveal(in: runtime, target: target))
        XCTAssertEqual(scroll.scrollOffset, 0)
        XCTAssertEqual(events.focusEntries, [4])
        return (item, receipt, target)
    }

    func close() {
        runtime.stopRenderLifecycleCallbacks()
        source.close()
        runtime.cancelRenderLifecycleTasks()
        scroll.setChildren([])
    }
}

private enum DemandReleaseFixtureError: Error { case unready }

@MainActor
private final class DemandReleaseEvents {
    var factories: [Int] = []
    var focusEntries: [Int] = []
}

@MainActor
private final class DemandReleaseLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { DemandReleaseEpoch() }
}

@MainActor
private final class DemandReleaseEpoch: RetainedBuildEpoch {
    private var prepared = false
    private var wasSuperseded = false
    var canAdopt: Bool { !prepared && !wasSuperseded }
    func supersede() { if !prepared { wasSuperseded = true } }
    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        prepared = true
        return true
    }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}
