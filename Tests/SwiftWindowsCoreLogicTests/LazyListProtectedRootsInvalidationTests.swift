import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest
@testable import SwiftWindowsUI

@MainActor
final class LazyListProtectedRootsInvalidationTests: XCTestCase {
    func testProtectionChangesAreNormalizedByLogicalRecord() async throws {
        let fixture = try ProtectedRootsFixture(heights: [[10, 10], [20], [20]])
        defer { fixture.close() }
        let leaves = fixture.content.children.filter { $0.dynamicContentIndex == 0 }
        XCTAssertEqual(leaves.count, 2)
        let first = try XCTUnwrap(leaves.first)
        let second = try XCTUnwrap(leaves.last)
        let next = try fixture.row(1)
        let firstToken = try XCTUnwrap(fixture.adapter.mountedToken(containing: first))
        XCTAssertEqual(fixture.adapter.mountedToken(containing: second), firstToken)
        let originalChildren = fixture.content.children.map(ObjectIdentifier.init)
        let originalFactories = fixture.events.factories
        let originalExtent = fixture.adapter.contentExtent

        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([]), .unchanged)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([ObjectIdentifier(first)]), .changed)
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([ObjectIdentifier(second)]), .unchanged)
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(
            fixture.adapter.updateProtectedRootsReportingChange([ObjectIdentifier(first), ObjectIdentifier(second)]),
            .unchanged)
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(
            fixture.adapter.updateProtectedRootsReportingChange([ObjectIdentifier(first), ObjectIdentifier(next)]),
            .changed)
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([ObjectIdentifier(next)]), .changed)
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([]), .changed)
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([]), .unchanged)

        XCTAssertEqual(fixture.content.children.map(ObjectIdentifier.init), originalChildren)
        XCTAssertEqual(fixture.events.factories, originalFactories)
        XCTAssertEqual(fixture.adapter.contentExtent, originalExtent)
        fixture.assertCleanAncestry()
    }

    func testRejectedProtectionPreservesAcceptedRootsAndBooleanCompatibility() async throws {
        let fixture = try ProtectedRootsFixture(heights: [[20], [20], [20]])
        defer { fixture.close() }
        let first = try fixture.row(0)
        let second = try fixture.row(1)
        let third = try fixture.row(2)
        let outsider = ViewNode()
        let tooManyRecords: Set<ObjectIdentifier> = [
            ObjectIdentifier(first), ObjectIdentifier(second), ObjectIdentifier(third),
        ]
        let originalChildren = fixture.content.children.map(ObjectIdentifier.init)
        let originalFactories = fixture.events.factories

        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([ObjectIdentifier(outsider)]), .rejected)
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange(tooManyRecords), .rejected)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([ObjectIdentifier(first)]), .changed)
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange(tooManyRecords), .rejected)
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([ObjectIdentifier(outsider)]), .rejected)
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([ObjectIdentifier(first)]), .unchanged)
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertTrue(fixture.adapter.updateProtectedRoots([ObjectIdentifier(first)]))
        XCTAssertFalse(fixture.adapter.updateProtectedRoots([ObjectIdentifier(outsider)]))
        XCTAssertTrue(fixture.adapter.updateProtectedRoots([ObjectIdentifier(second)]))
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([ObjectIdentifier(second)]), .unchanged)
        XCTAssertTrue(fixture.adapter.updateProtectedRoots([]))
        XCTAssertEqual(fixture.adapter.updateProtectedRootsReportingChange([]), .unchanged)

        XCTAssertEqual(fixture.content.children.map(ObjectIdentifier.init), originalChildren)
        XCTAssertEqual(fixture.events.factories, originalFactories)
        fixture.assertCleanAncestry()
    }

    func testUnchangedEmptyRequestKeepsOriginalSettlement() async throws {
        let fixture = try ProtectedRootsFixture()
        defer { fixture.close() }
        let item = try fixture.target(1)
        XCTAssertEqual(item.knownLeafCount, 0)
        guard case .settled(let settlement) = fixture.runtime.layoutSettlementStatus else {
            return XCTFail("The baseline must have an actual settled receipt")
        }
        let originalPass = fixture.runtime.layoutPassID
        let originalVisits = fixture.runtime.layoutVisitCount
        let originalFactories = fixture.events.factories
        let originalBuilds = fixture.lease.beginCalls

        fixture.runtime.withLazyListResolutionBudget {
            guard case .empty = fixture.runtime.resolveLazyListTarget(item) else {
                return XCTFail("An unchanged known-empty request must remain empty")
            }
        }

        XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
        XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(settlement))
        XCTAssertEqual(fixture.runtime.layoutPassID, originalPass)
        XCTAssertEqual(fixture.runtime.layoutVisitCount, originalVisits)
        XCTAssertEqual(fixture.events.factories, originalFactories)
        XCTAssertEqual(fixture.lease.beginCalls, originalBuilds)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 0)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        fixture.assertCleanAncestry()
    }

    func testChangedEmptyRequestInvalidatesCleanAncestorsBeforeReturning() async throws {
        let fixture = try ProtectedRootsFixture()
        defer { fixture.close() }
        let receipt = try fixture.prepareAction()
        defer { receipt.cancelPreparedNavigation() }
        let item = try fixture.target(1)
        XCTAssertEqual(item.knownLeafCount, 0)
        let originalPass = fixture.runtime.layoutPassID
        let originalVisits = fixture.runtime.layoutVisitCount
        let originalFactories = fixture.events.factories
        let originalBuilds = fixture.lease.beginCalls
        fixture.assertCleanAncestry()

        fixture.runtime.withLazyListResolutionBudget {
            guard case .empty = fixture.runtime.resolveLazyListTarget(item) else {
                return XCTFail("Changed protection does not make a known-empty record nonempty")
            }
            XCTAssertEqual(fixture.runtime.layoutPassID, originalPass)
            XCTAssertEqual(fixture.runtime.layoutVisitCount, originalVisits)
            XCTAssertEqual(fixture.events.factories, originalFactories)
            XCTAssertEqual(fixture.lease.beginCalls, originalBuilds)
            XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
            fixture.assertLayoutDirtyAncestry()

            // One ordinary query services the newly requested work in the same budget.
            XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.content))
            fixture.assertContentReached(after: originalPass)
            XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
            XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
            XCTAssertTrue(receipt.permitsBindingWrite)
            XCTAssertEqual(fixture.events.factories, originalFactories)
        }
        fixture.assertDefaultBudgetBounds()
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
    }

    func testChangedMountedRequestPreflightReachesContentThroughCleanWrapper() async throws {
        let fixture = try ProtectedRootsFixture(heights: [[20], [20], [20]])
        defer { fixture.close() }
        let receipt = try fixture.prepareAction()
        defer { receipt.cancelPreparedNavigation() }
        let item = try fixture.target(1)
        defer { fixture.runtime.releaseLazyListTarget(item) }
        let expectedRow = try fixture.row(1)
        let originalPass = fixture.runtime.layoutPassID
        let originalFactories = fixture.events.factories
        fixture.assertCleanAncestry()
        XCTAssertEqual(fixture.content.children.count, 3)
        XCTAssertEqual(fixture.adapter.contentExtent, 60)
        XCTAssertEqual(fixture.scroll.resolvedFrame.size.height, 60)
        for row in fixture.content.children {
            let token = try XCTUnwrap(fixture.adapter.mountedToken(containing: row))
            XCTAssertEqual(fixture.adapter.knownLeafCount(for: token), 1)
        }

        fixture.runtime.withLazyListResolutionBudget {
            // These three measured visible rows need no construction. The original
            // distant keyboard test separately requires deferred-row navigation.
            guard case .ready(let roots) = fixture.runtime.resolveLazyListTarget(item) else {
                return XCTFail("A measured mounted record must become ready within the original budget")
            }
            XCTAssertEqual(roots.count, 1)
            XCTAssertTrue(roots.first === expectedRow)
            fixture.assertContentReached(after: originalPass)
            XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
            XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
            XCTAssertTrue(receipt.permitsBindingWrite)
            XCTAssertEqual(fixture.events.factories, originalFactories)
        }
        fixture.assertDefaultBudgetBounds()
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
    }

    func testAfterLayoutChangedProtectionInvalidatesAnAlreadyActiveDemand() async throws {
        let fixture = try ProtectedRootsFixture(heights: [[20], [20], [20]])
        defer { fixture.close() }
        let receipt = try fixture.prepareAction()
        defer { receipt.cancelPreparedNavigation() }
        let item = try fixture.target(1)
        defer { fixture.runtime.releaseLazyListTarget(item) }
        let targetOwner = try XCTUnwrap(try fixture.row(1).listNavigationOwner)
        let originalFactories = fixture.events.factories
        var firstCalls = 0
        var secondCalls = 0
        var secondEntryPass = fixture.runtime.layoutPassID

        fixture.runtime.scheduleAfterLayout(key: "protected-roots-first-demand") {
            firstCalls += 1
            let pass = fixture.runtime.layoutPassID
            let visits = fixture.runtime.layoutVisitCount
            XCTAssertTrue(receipt.permitsBindingWrite)
            XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
            guard case .pending = fixture.runtime.resolveLazyListTarget(item) else {
                return XCTFail("The first after-layout call must install its real logical demand")
            }
            XCTAssertEqual(fixture.runtime.layoutPassID, pass)
            XCTAssertEqual(fixture.runtime.layoutVisitCount, visits)
            XCTAssertEqual(fixture.events.factories, originalFactories)
            XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
            fixture.assertLayoutDirtyAncestry()
        }
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.content))
        XCTAssertEqual(firstCalls, 1)
        fixture.assertDefaultBudgetBounds()
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)

        // Display the first request's work before scheduling its next opportunity.
        // A callback during render would leave pending dirty nodes at endRenderPass.
        _ = fixture.runtime.renderFrame()
        fixture.assertDefaultBudgetBounds()
        fixture.assertCleanAncestry()
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        XCTAssertTrue(receipt.permitsBindingWrite)
        XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(item))

        fixture.runtime.scheduleAfterLayout(key: "protected-roots-existing-demand") {
            secondCalls += 1
            secondEntryPass = fixture.runtime.layoutPassID
            let visits = fixture.runtime.layoutVisitCount
            fixture.assertCleanAncestry()
            XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
            XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
            // Physical source 0 and destination 1, plus logical demand 1, use
            // exactly two protected records and the same original receipt.
            XCTAssertTrue(receipt.prepareTarget(targetOwner))
            fixture.assertCleanAncestry()
            guard case .pending = fixture.runtime.resolveLazyListTarget(item) else {
                return XCTFail("Changed protection must remain pending until owned post-callback layout")
            }
            XCTAssertEqual(fixture.runtime.layoutPassID, secondEntryPass)
            XCTAssertEqual(fixture.runtime.layoutVisitCount, visits)
            XCTAssertEqual(fixture.events.factories, originalFactories)
            XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
            fixture.assertLayoutDirtyAncestry()
            XCTAssertTrue(receipt.permitsBindingWrite)
        }
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.content))
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(secondCalls, 1)
        fixture.assertContentReached(after: secondEntryPass)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
        XCTAssertTrue(receipt.permitsBindingWrite)
        XCTAssertEqual(fixture.events.factories, originalFactories)
        fixture.assertDefaultBudgetBounds()
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
    }

    func testGridCallbackRetirementRevokesOriginalEmptyItemBeforeReturn() async throws {
        let fixture = try ProtectedRootsFixture(inGrid: true)
        defer { fixture.close() }
        let gridRow = try XCTUnwrap(fixture.gridRow)
        let receipt = try fixture.prepareAction()
        defer { receipt.cancelPreparedNavigation() }
        let item = try fixture.target(1)
        XCTAssertEqual(item.knownLeafCount, 0)
        let baselineContentPass = fixture.content.lastLayoutVisitPassID
        let originalFactories = fixture.events.factories
        let originalOffset = fixture.scroll.scrollOffset
        let originalFocus = fixture.runtime.focusedNode.map(ObjectIdentifier.init)
        let probe = ProtectedRootsRetirementProbe()
        let collisionKey = "grid-shared-tracks-\(ObjectIdentifier(fixture.wrapper))"
        var armed = false
        var inDriver = false
        var driverCalls = 0
        var rowCalls = 0

        gridRow.onLayout = { _ in
            guard armed else { return }
            armed = false
            rowCalls += 1
            XCTAssertTrue(inDriver)
            XCTAssertTrue(fixture.runtime.isLayoutInProgress)
            XCTAssertEqual(fixture.content.lastLayoutVisitPassID, baselineContentPass)
            XCTAssertGreaterThan(fixture.runtime.layoutPassID, baselineContentPass)
            XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
            XCTAssertEqual(fixture.adapter.knownLeafCount(for: item.token), 0)
            XCTAssertTrue(receipt.permitsBindingWrite)

            // Grid has published its actual track plan before visiting this row.
            // Seed after the outer drain copied its callbacks, and let the helper
            // return so only the pending callback owns the retirement payload.
            Self.installCollisionCapture(fixture: fixture, item: item, probe: probe, key: collisionKey)
            XCTAssertNotNil(probe.payload)
            XCTAssertEqual(probe.retirementCalls, 0)
            probe.isResolving = true
            let result = fixture.runtime.resolveLazyListTarget(item)
            probe.isResolving = false

            guard case .obsolete = result else {
                return XCTFail("Protection invalidation must recheck the original item after callback retirement")
            }
            XCTAssertNil(probe.payload)
            XCTAssertEqual(probe.retirementCalls, 1)
            XCTAssertTrue(probe.retiredWhileResolving)
            XCTAssertTrue(probe.retiredDuringLayout)
            XCTAssertEqual(probe.itemCurrentAfterClose, false)
            XCTAssertEqual(probe.callbackBodyCalls, 0)
            XCTAssertFalse(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
            XCTAssertNil(fixture.adapter.knownLeafCount(for: item.token))
            XCTAssertEqual(fixture.events.factories, originalFactories)
            XCTAssertEqual(fixture.scroll.scrollOffset, originalOffset)
            XCTAssertEqual(fixture.runtime.focusedNode.map(ObjectIdentifier.init), originalFocus)
        }
        fixture.assertCleanAncestry()
        XCTAssertEqual(gridRow.virtualizationDescentPassID, 0)
        fixture.runtime.scheduleAfterLayout(key: "protected-roots-grid-driver") {
            driverCalls += 1
            inDriver = true
            armed = true
            // This real property change invalidates Grid's cached plan before
            // nested layout; no property is changed between seeding and resolve.
            gridRow.preferredSize = Size(width: 121, height: 60)
            _ = fixture.runtime.activatableControlCenters()
            inDriver = false
        }
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.root))

        XCTAssertEqual(driverCalls, 1)
        XCTAssertEqual(rowCalls, 1)
        XCTAssertEqual(probe.retirementCalls, 1)
        XCTAssertTrue(probe.retiredWhileResolving)
        XCTAssertEqual(probe.callbackBodyCalls, 0)
        XCTAssertNil(probe.payload)
        XCTAssertFalse(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
        XCTAssertNil(fixture.adapter.knownLeafCount(for: item.token))
        XCTAssertEqual(fixture.events.factories, originalFactories)
        XCTAssertEqual(fixture.scroll.scrollOffset, originalOffset)
        XCTAssertEqual(fixture.runtime.focusedNode.map(ObjectIdentifier.init), originalFocus)
        fixture.assertDefaultBudgetBounds()
    }

    @inline(never)
    private static func installCollisionCapture(
        fixture: ProtectedRootsFixture, item: RetainedLazyListAccessibilityItem,
        probe: ProtectedRootsRetirementProbe, key: String
    ) {
        let payload = ProtectedRootsRetirementPayload(
            source: fixture.source, runtime: fixture.runtime, item: item, probe: probe)
        probe.payload = payload
        fixture.runtime.scheduleAfterLayout(key: key) {
            probe.callbackBodyCalls += 1
            withExtendedLifetime(payload) {}
        }
    }
}

@MainActor
private final class ProtectedRootsFixture {
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let lease: ProtectedRootsBuildLease
    let root: ViewNode
    let wrapper: ViewNode
    let gridRow: ViewNode?
    let scroll: ViewNode
    let content: ViewNode
    let runtime: RetainedViewRuntime
    let scope: RetainedListNavigationOwner
    let events: ProtectedRootsEvents

    init(heights: [[Double]] = [[20], [], [20]], inGrid: Bool = false) throws {
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
        let content = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
        let lease = ProtectedRootsBuildLease()
        content.retainedViewIdentity = identity
        content.retainedSubtreeBuildLease = lease
        let bounds = Rect(x: 0, y: 0, width: 120, height: 60)
        let scroll = ViewNode(
            frame: bounds, clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical,
            children: [content])
        let gridRow: ViewNode?
        let wrapper: ViewNode
        if inGrid {
            let row = ViewNode(layoutMode: .gridRow(.init()), isHitTestVisible: false, children: [scroll])
            gridRow = row
            wrapper = ViewNode(
                frame: bounds,
                layoutMode: .grid(
                    .init(
                        horizontalSpacing: 0, verticalSpacing: 0,
                        horizontalAlignment: .leading, verticalAlignment: .leading)),
                isHitTestVisible: false, children: [row])
        } else {
            gridRow = nil
            wrapper = ViewNode(frame: bounds, children: [scroll])
        }
        let root = ViewNode(frame: bounds, children: [wrapper])
        let runtime = RetainedViewRuntime(root: root)
        let scope = RetainedListNavigationOwner(runtime: runtime)
        scope.install(on: scroll)
        let events = ProtectedRootsEvents()
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            source.replaceData(Array(heights.indices), id: \.self, identityRoot: identity) { value, prefix in
                events.factories.append(value)
                return heights[value].enumerated().map { leaf, height in
                    let row = ViewNode(
                        preferredSize: Size(width: 120, height: height), isFocusable: true,
                        accessibilityTraits: .isSelectable)
                    row.retainedViewIdentity = prefix.appending(.slot(leaf)).appending(.role(.row))
                    row.dynamicContentIndex = value
                    row.interceptsVerticalArrowKeys = true
                    _ = scope.makeRowOwner(on: row)
                    return row
                }
            })
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 16, maximumMountedLeaves: 16, maximumProtectedRecords: 2))
        content.retainedLazyListAdapter = adapter
        self.source = source
        self.adapter = adapter
        self.lease = lease
        self.root = root
        self.wrapper = wrapper
        self.gridRow = gridRow
        self.scroll = scroll
        self.content = content
        self.runtime = runtime
        self.scope = scope
        self.events = events

        // Explicit ordinary fixture construction, before any item or action:
        // one layout query mounts the tiny list, one paint clears its dirty bits.
        // No loop, custom clock, or budget override prepares these regressions.
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root))
        assertDefaultBudgetBounds()
        _ = runtime.renderFrame()
        assertDefaultBudgetBounds()
        assertCleanAncestry()
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertEqual(events.factories, Array(heights.indices))
        XCTAssertEqual(root.virtualizationDescentPassID, 0)
        XCTAssertEqual(wrapper.virtualizationDescentPassID, 0)
        XCTAssertNotNil(root.cachedLayoutKey)
        XCTAssertNotNil(wrapper.cachedLayoutKey)
    }

    func row(_ value: Int) throws -> ViewNode {
        try XCTUnwrap(content.children.first { $0.dynamicContentIndex == value })
    }

    func target(_ value: Int) throws -> RetainedLazyListAccessibilityItem {
        try XCTUnwrap(runtime.lazyListTarget(in: content, key: .init(value)))
    }

    func prepareAction() throws -> RetainedListNavigationReceipt {
        let owner = try XCTUnwrap(try row(0).listNavigationOwner)
        return try XCTUnwrap(scope.prepareAction(from: owner))
    }

    private var ancestry: [ViewNode] {
        [root, wrapper] + (gridRow.map { [$0] } ?? []) + [scroll, content]
    }

    func assertCleanAncestry(file: StaticString = #filePath, line: UInt = #line) {
        for node in ancestry {
            XCTAssertTrue(node.subtreeDirtyFlags.isEmpty, file: file, line: line)
        }
    }

    func assertLayoutDirtyAncestry(file: StaticString = #filePath, line: UInt = #line) {
        for node in ancestry {
            XCTAssertTrue(node.subtreeDirtyFlags.contains(.layout), file: file, line: line)
        }
    }

    func assertContentReached(after pass: UInt64, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(runtime.layoutPassID, pass, file: file, line: line)
        for node in ancestry {
            XCTAssertEqual(node.lastLayoutVisitPassID, runtime.layoutPassID, file: file, line: line)
        }
    }

    func assertDefaultBudgetBounds(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(runtime.lastLazyListConsumedRounds, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedRounds, 4, file: file, line: line)
        XCTAssertGreaterThanOrEqual(runtime.lastLazyListConsumedElements, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedElements, 128, file: file, line: line)
    }

    func close() {
        gridRow?.onLayout = nil
        runtime.stopRenderLifecycleCallbacks()
        source.close()
        runtime.cancelRenderLifecycleTasks()
        root.setChildren([])
    }
}

@MainActor
private final class ProtectedRootsEvents {
    var factories: [Int] = []
}

@MainActor
private final class ProtectedRootsBuildLease: RetainedSubtreeBuildLease {
    private(set) var beginCalls = 0
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? {
        beginCalls += 1
        return ProtectedRootsBuildEpoch()
    }
}

@MainActor
private final class ProtectedRootsBuildEpoch: RetainedBuildEpoch {
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

@MainActor
private final class ProtectedRootsRetirementProbe {
    weak var payload: ProtectedRootsRetirementPayload?
    var isResolving = false
    var retirementCalls = 0
    var callbackBodyCalls = 0
    var retiredWhileResolving = false
    var retiredDuringLayout = false
    var itemCurrentAfterClose: Bool?
}

@MainActor
private final class ProtectedRootsRetirementPayload {
    private let source: RetainedLazyListDataSource<Int, [ViewNode]>
    private weak var runtime: RetainedViewRuntime?
    private let item: RetainedLazyListAccessibilityItem
    private let probe: ProtectedRootsRetirementProbe

    init(
        source: RetainedLazyListDataSource<Int, [ViewNode]>, runtime: RetainedViewRuntime,
        item: RetainedLazyListAccessibilityItem, probe: ProtectedRootsRetirementProbe
    ) {
        self.source = source
        self.runtime = runtime
        self.item = item
        self.probe = probe
    }

    deinit {
        MainActor.assumeIsolated {
            probe.retirementCalls += 1
            probe.retiredWhileResolving = probe.isResolving
            probe.retiredDuringLayout = runtime?.isLayoutInProgress == true
            source.close()
            probe.itemCurrentAfterClose = runtime?.isLazyListAccessibilityItemCurrent(item)
        }
    }
}
