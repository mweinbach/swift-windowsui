import SwiftWindowsCore
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI

/// Headless coverage for the native navigation lifetime used by
/// public lazy Lists. These fixtures do not exercise a platform host or UIA.
@MainActor
final class PublicLazyListNavigationLifetimeTests: XCTestCase {
    func testPreparedReplayOwnsItsRequestUntilNormalDelivery() async throws {
        let fixture = try NavigationLifetimeFixture()
        defer { fixture.close() }
        let events = NavigationReplayEvents()
        var request: NavigationLifetimeRequest? = try fixture.pendingRequest(events: events)
        weak var weakRequest = request
        weak var weakTarget = request?.logicalTarget
        XCTAssertTrue(try XCTUnwrap(request).schedule())

        request = nil

        XCTAssertNotNil(weakRequest)
        XCTAssertNotNil(weakTarget)
        XCTAssertEqual(events.deliveries, [])
        XCTAssertEqual(events.cancellations, 0)
        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(events.deliveries, ["layout"])
        XCTAssertEqual(events.completions, 1)
        XCTAssertEqual(events.cancellations, 0)
        XCTAssertEqual(events.releases, 1)
        XCTAssertNil(weakRequest)
        XCTAssertNil(weakTarget)
        XCTAssertFalse(fixture.events.factories.contains(175))
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(events.completions, 1)
        XCTAssertEqual(events.cancellations, 0)
    }

    func testSameReceiptMovesFromLayoutToIdleWithoutCancellation() async throws {
        let fixture = try NavigationLifetimeFixture()
        defer { fixture.close() }
        let events = NavigationReplayEvents()
        var request: NavigationLifetimeRequest? = try fixture.pendingRequest(events: events)
        weak var weakRequest = request
        weak var weakTarget = request?.logicalTarget
        XCTAssertTrue(try XCTUnwrap(request).schedule(waitForIdle: true))
        request = nil

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(events.deliveries, ["layout", "idle"])
        XCTAssertEqual(events.layoutDeliveryWasIdle, false)
        XCTAssertEqual(events.idleDeliveryWasIdle, true)
        XCTAssertEqual(events.handoffAccepted, true)
        XCTAssertEqual(events.completions, 1)
        XCTAssertEqual(events.cancellations, 0)
        XCTAssertEqual(events.releases, 1)
        XCTAssertNil(weakRequest)
        XCTAssertNil(weakTarget)
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(events.deliveries, ["layout", "idle"])
    }

    func testNewAdmittedActionCancelsAndReleasesThePreviousRequestOnce() async throws {
        let fixture = try NavigationLifetimeFixture()
        defer { fixture.close() }
        let events = NavigationReplayEvents()
        var request: NavigationLifetimeRequest? = try fixture.pendingRequest(events: events)
        weak var weakRequest = request
        weak var weakTarget = request?.logicalTarget
        XCTAssertTrue(try XCTUnwrap(request).schedule())
        request = nil

        let replacement = try fixture.prepareAction()

        XCTAssertTrue(replacement.permitsBindingWrite)
        XCTAssertEqual(events.deliveries, [])
        XCTAssertEqual(events.cancellations, 1)
        XCTAssertEqual(events.releases, 1)
        XCTAssertNil(weakRequest)
        XCTAssertNil(weakTarget)
        replacement.cancelPreparedNavigation()
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 8))
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(events.cancellations, 1)
        XCTAssertEqual(events.completions, 0)
        XCTAssertFalse(fixture.events.factories.contains(175))
    }

    func testExternalFocusCancelsTheStaleDeliveryInsteadOfRunningIt() async throws {
        let fixture = try NavigationLifetimeFixture()
        defer { fixture.close() }
        let alternate = try fixture.row(1)
        let events = NavigationReplayEvents()
        var request: NavigationLifetimeRequest? = try fixture.pendingRequest(events: events)
        weak var weakRequest = request
        weak var weakTarget = request?.logicalTarget
        XCTAssertTrue(try XCTUnwrap(request).schedule())
        request = nil

        fixture.runtime.requestFocus(alternate)
        _ = fixture.runtime.renderFrame()

        XCTAssertTrue(fixture.runtime.focusedNode === alternate)
        XCTAssertEqual(events.deliveries, [])
        XCTAssertEqual(events.completions, 0)
        XCTAssertEqual(events.cancellations, 1)
        XCTAssertEqual(events.releases, 1)
        XCTAssertNil(weakRequest)
        XCTAssertNil(weakTarget)
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(events.cancellations, 1)
        XCTAssertTrue(fixture.runtime.focusedNode === alternate)
    }

    func testRefusedSchedulingDoesNotRegisterACancellationCallback() async throws {
        let fixture = try NavigationLifetimeFixture()
        defer { fixture.close() }
        let alternate = try fixture.row(1)
        let events = NavigationReplayEvents()
        var request: NavigationLifetimeRequest? = try fixture.pendingRequest(events: events)
        weak var weakRequest = request
        weak var weakTarget = request?.logicalTarget
        fixture.runtime.requestFocus(alternate)

        XCTAssertFalse(try XCTUnwrap(request).schedule())
        request = nil

        XCTAssertEqual(events.deliveries, [])
        XCTAssertEqual(events.cancellations, 0)
        XCTAssertEqual(events.releases, 1)
        XCTAssertNil(weakRequest)
        XCTAssertNil(weakTarget)
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 8))
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(events.cancellations, 0)
        XCTAssertFalse(fixture.events.factories.contains(175))
        XCTAssertTrue(fixture.runtime.focusedNode === alternate)
    }

    func testDepartureRevokesTheRequestBeforeDisappearanceCleanup() async throws {
        let fixture = try NavigationLifetimeFixture()
        defer { fixture.close() }
        let sourceRow = try fixture.row(0)
        let events = NavigationReplayEvents()
        var request: NavigationLifetimeRequest? = try fixture.pendingRequest(events: events)
        weak var weakRequest = request
        weak var weakTarget = request?.logicalTarget
        XCTAssertTrue(try XCTUnwrap(request).schedule())
        sourceRow.onDisappear = {
            events.departureSawRetainedRequest = weakRequest != nil
            events.departureSawRevokedRequest = weakRequest?.receipt.permitsContinuation == false
            events.cancellationsDuringDeparture = events.cancellations
        }
        request = nil

        fixture.scroll.setChildren([])

        XCTAssertEqual(events.departureSawRetainedRequest, true)
        XCTAssertEqual(events.departureSawRevokedRequest, true)
        XCTAssertEqual(events.cancellationsDuringDeparture, 0)
        XCTAssertEqual(events.deliveries, [])
        XCTAssertEqual(events.cancellations, 1)
        XCTAssertEqual(events.releases, 1)
        XCTAssertNil(weakRequest)
        XCTAssertNil(weakTarget)
        sourceRow.onDisappear = nil
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(events.cancellations, 1)
    }

    func testHostStopPreservesCapturesUntilTerminalTaskCleanup() async throws {
        let fixture = try NavigationLifetimeFixture()
        defer { fixture.close() }
        let events = NavigationReplayEvents()
        var request: NavigationLifetimeRequest? = try fixture.pendingRequest(events: events)
        weak var weakRequest = request
        weak var weakTarget = request?.logicalTarget
        XCTAssertTrue(try XCTUnwrap(request).schedule())
        request = nil

        fixture.runtime.stopRenderLifecycleCallbacks()

        XCTAssertEqual(weakRequest?.receipt.permitsContinuation, false)
        XCTAssertNotNil(weakRequest)
        XCTAssertNotNil(weakTarget)
        XCTAssertEqual(events.deliveries, [])
        XCTAssertEqual(events.cancellations, 0)
        XCTAssertEqual(events.releases, 0)
        fixture.runtime.cancelRenderLifecycleTasks()

        XCTAssertEqual(events.cancellations, 1)
        XCTAssertEqual(events.cancellationSawClosedRuntime, true)
        XCTAssertEqual(events.releases, 1)
        XCTAssertNil(weakRequest)
        XCTAssertNil(weakTarget)
        fixture.runtime.stopRenderLifecycleCallbacks()
        fixture.runtime.cancelRenderLifecycleTasks()
        _ = fixture.runtime.renderFrame()
        XCTAssertEqual(events.deliveries, [])
        XCTAssertEqual(events.cancellations, 1)
        XCTAssertEqual(events.releases, 1)
    }

    func testDeferredCancellationCrossingHostStopWaitsForTerminalCleanup() async throws {
        let fixture = try NavigationLifetimeFixture()
        defer { fixture.close() }
        let events = NavigationReplayEvents()
        var request: NavigationLifetimeRequest? = try fixture.pendingRequest(events: events)
        weak var weakRequest = request
        weak var weakTarget = request?.logicalTarget
        XCTAssertTrue(try XCTUnwrap(request).schedule())
        request = nil

        fixture.runtime.beginLongPressReconciliation()
        weakRequest?.receipt.cancelPreparedNavigation()
        fixture.runtime.stopRenderLifecycleCallbacks()
        fixture.runtime.endLongPressReconciliation()

        XCTAssertEqual(events.cancellations, 0)
        XCTAssertEqual(events.releases, 0)
        XCTAssertNotNil(weakRequest)
        XCTAssertNotNil(weakTarget)
        fixture.runtime.cancelRenderLifecycleTasks()

        XCTAssertEqual(events.deliveries, [])
        XCTAssertEqual(events.cancellations, 1)
        XCTAssertEqual(events.cancellationSawClosedRuntime, true)
        XCTAssertEqual(events.releases, 1)
        XCTAssertNil(weakRequest)
        XCTAssertNil(weakTarget)
    }

    func testAcceptedRevealFinishesFocusAcrossBoundedOrdinaryRenders() async throws {
        let fixture = try NavigationLifetimeFixture()
        defer { fixture.close() }
        let sourceRow = try fixture.row(0)
        var receipt: RetainedListNavigationReceipt? = try fixture.prepareAction()
        weak var weakReceipt = receipt
        var item: RetainedLazyListAccessibilityItem? = try XCTUnwrap(
            fixture.runtime.lazyListTarget(in: fixture.list, key: .init(175)))
        weak var weakItem = item
        let target = try XCTUnwrap(fixture.runtime.realizeLazyListTarget(try XCTUnwrap(item)))
        let targetOwner = try XCTUnwrap(target.listNavigationOwner)
        XCTAssertTrue(try XCTUnwrap(receipt).prepareTarget(targetOwner, requiresRevealBeforeFocus: true))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 8))
        let focusRevision = fixture.runtime.presentationFocusRevision
        let factoriesBeforeReveal = fixture.events.factories.count

        let finished = fixture.runtime.withLazyListResolutionBudget {
            receipt?.finishNavigation() ?? false
        }

        XCTAssertFalse(finished, "The new viewport requires more than one neighboring row")
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0, "The initial reveal was accepted exactly once")
        XCTAssertNil(fixture.runtime.focusedNode, "A partially constructed viewport cannot grant focus")
        XCTAssertEqual(fixture.events.focusEntries, [])
        XCTAssertLessThanOrEqual(fixture.events.factories.count - factoriesBeforeReveal, 1)
        fixture.runtime.releaseLazyListTarget(try XCTUnwrap(item))
        item = nil
        receipt = nil
        XCTAssertNil(weakItem)
        XCTAssertNotNil(weakReceipt, "The native continuation owns the accepted action until settlement")

        for _ in 0..<16 where fixture.runtime.focusedNode !== target {
            let factoriesBeforeFrame = fixture.events.factories.count
            _ = fixture.runtime.renderFrame()
            XCTAssertLessThanOrEqual(fixture.events.factories.count - factoriesBeforeFrame, 1)
            XCTAssertTrue(target.parent === fixture.list)
            if fixture.runtime.focusedNode == nil {
                XCTAssertTrue(
                    sourceRow.parent === fixture.list, "Both original endpoints remain protected while waiting")
                XCTAssertEqual(fixture.events.focusEntries, [])
            }
        }

        XCTAssertTrue(fixture.runtime.focusedNode === target)
        XCTAssertTrue(target.isFocused)
        XCTAssertFalse(target.isLayoutDeferredByVirtualization)
        XCTAssertGreaterThan(target.resolvedFrame.maxY, fixture.scroll.resolvedScrollOffset)
        XCTAssertLessThan(
            target.resolvedFrame.minY, fixture.scroll.resolvedScrollOffset + fixture.scroll.resolvedFrame.height)
        XCTAssertEqual(fixture.events.focusEntries, [175])
        XCTAssertEqual(fixture.events.factories.filter { $0 == 175 }.count, 1)
        XCTAssertEqual(fixture.runtime.presentationFocusRevision, focusRevision + 1)
        XCTAssertNil(weakReceipt, "The completed native continuation releases its one-shot receipt")
        let factoriesBeforeFinalFrame = fixture.events.factories.count
        _ = fixture.runtime.renderFrame()
        XCTAssertLessThanOrEqual(fixture.events.factories.count - factoriesBeforeFinalFrame, 1)
        XCTAssertEqual(fixture.events.focusEntries, [175])
        XCTAssertTrue(fixture.runtime.focusedNode === target)
    }

    func testFocusExitLayoutQueryConsumesRevealWithoutEnteringTheTarget() async throws {
        let fixture = try NavigationLifetimeFixture()
        defer { fixture.close() }
        let sourceRow = try fixture.row(0)
        fixture.runtime.requestFocus(sourceRow)
        XCTAssertTrue(fixture.runtime.focusedNode === sourceRow)
        let receipt = try fixture.prepareAction()
        let item = try XCTUnwrap(fixture.runtime.lazyListTarget(in: fixture.list, key: .init(175)))
        defer { fixture.runtime.releaseLazyListTarget(item) }
        let target = try XCTUnwrap(fixture.runtime.realizeLazyListTarget(item))
        let targetOwner = try XCTUnwrap(target.listNavigationOwner)
        XCTAssertTrue(receipt.prepareTarget(targetOwner, requiresRevealBeforeFocus: true))
        var exitQueries = 0
        var queryExpiredSettlement = false
        sourceRow.onFocusExit = { [weak runtime = fixture.runtime] in
            guard let runtime else { return }
            guard case .settled(let settlement) = runtime.layoutSettlementStatus else {
                return XCTFail("The terminal focus exit must start with the accepted reveal's settled layout")
            }
            XCTAssertTrue(runtime.isListNavigationGeometryCurrent(receipt))
            exitQueries += 1
            // A clean query advances the resolution sequence without an
            // application layout mutation or a different scroll/focus intent.
            XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
            XCTAssertTrue(runtime.isListNavigationGeometryCurrent(receipt))
            queryExpiredSettlement = !runtime.isLayoutSettlementReceiptCurrent(settlement)
        }
        defer { sourceRow.onFocusExit = nil }

        XCTAssertFalse(receipt.finishNavigation())

        XCTAssertEqual(exitQueries, 1)
        XCTAssertTrue(queryExpiredSettlement)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0)
        XCTAssertEqual(fixture.events.focusEntries, [0])
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertFalse(target.isFocused)
        XCTAssertFalse(receipt.permitsContinuation)
        XCTAssertFalse(receipt.finishNavigation(), "The expired terminal focus proof cannot be retried")
        for _ in 0..<4 { _ = fixture.runtime.renderFrame() }
        XCTAssertEqual(exitQueries, 1)
        XCTAssertEqual(fixture.events.focusEntries, [0])
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertFalse(target.isFocused)
    }
}

@MainActor
private final class NavigationReplayEvents {
    var deliveries: [String] = []
    var completions = 0
    var cancellations = 0
    var releases = 0
    var handoffAccepted: Bool?
    var layoutDeliveryWasIdle: Bool?
    var idleDeliveryWasIdle: Bool?
    var departureSawRetainedRequest: Bool?
    var departureSawRevokedRequest: Bool?
    var cancellationsDuringDeparture: Int?
    var cancellationSawClosedRuntime: Bool?
}

/// The runtime and nodes are weak. Only the native queue may keep this app
/// request alive after its caller drops it; no request owns a callback to itself.
@MainActor
private final class NavigationLifetimeRequest {
    let receipt: RetainedListNavigationReceipt
    private(set) var logicalTarget: RetainedLazyListAccessibilityItem?
    private weak var runtime: RetainedViewRuntime?
    private let events: NavigationReplayEvents

    init(
        runtime: RetainedViewRuntime, receipt: RetainedListNavigationReceipt,
        target: RetainedLazyListAccessibilityItem, events: NavigationReplayEvents
    ) {
        self.runtime = runtime
        self.receipt = receipt
        logicalTarget = target
        self.events = events
    }

    isolated deinit { events.releases += 1 }

    func schedule(waitForIdle: Bool = false) -> Bool {
        receipt.schedulePreparedNavigationReplay(
            afterLayout: true,
            perform: { [self] in
                events.deliveries.append("layout")
                events.layoutDeliveryWasIdle = runtime?.canPrepareLayoutSettlement
                if waitForIdle {
                    events.handoffAccepted = receipt.schedulePreparedNavigationReplay(
                        afterLayout: false,
                        perform: { [self] in
                            events.deliveries.append("idle")
                            events.idleDeliveryWasIdle = runtime?.canPrepareLayoutSettlement
                            complete()
                        },
                        onCancel: { [self] in cancel() })
                } else {
                    complete()
                }
            },
            onCancel: { [self] in cancel() })
    }

    private func complete() {
        events.completions += 1
        releaseTarget()
    }

    private func cancel() {
        events.cancellations += 1
        events.cancellationSawClosedRuntime = runtime?.permitsRetainedActionInvocation == false
        releaseTarget()
    }

    private func releaseTarget() {
        if let logicalTarget { runtime?.releaseLazyListTarget(logicalTarget) }
        logicalTarget = nil
    }
}

@MainActor
private final class NavigationLifetimeEvents {
    var factories: [Int] = []
    var focusEntries: [Int] = []
}

@MainActor
private final class NavigationLifetimeFixture {
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let list: ViewNode
    let scroll: ViewNode
    let runtime: RetainedViewRuntime
    let scope: RetainedListNavigationOwner
    let events: NavigationLifetimeEvents

    init() throws {
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
        let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
        list.retainedViewIdentity = identity
        list.retainedSubtreeBuildLease = NavigationLifetimeLease()
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 100), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical, children: [list])
        let runtime = RetainedViewRuntime(root: scroll)
        let scope = RetainedListNavigationOwner(runtime: runtime)
        scope.install(on: scroll)
        let events = NavigationLifetimeEvents()
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            source.replaceData(Array(0..<1000), id: \.self, identityRoot: identity) { value, prefix in
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
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 16, maximumMountedLeaves: 16, maximumProtectedRecords: 2))
        runtime.clock = { 0 }
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 8))
        self.source = source
        self.list = list
        self.scroll = scroll
        self.runtime = runtime
        self.scope = scope
        self.events = events
        _ = runtime.renderFrame()
    }

    func row(_ value: Int) throws -> ViewNode {
        try XCTUnwrap(list.children.first { $0.dynamicContentIndex == value })
    }

    func prepareAction() throws -> RetainedListNavigationReceipt {
        let sourceOwner = try XCTUnwrap(try row(0).listNavigationOwner)
        return try XCTUnwrap(scope.prepareAction(from: sourceOwner))
    }

    func pendingRequest(events: NavigationReplayEvents) throws -> NavigationLifetimeRequest {
        let receipt = try prepareAction()
        let target = try XCTUnwrap(runtime.lazyListTarget(in: list, key: .init(175)))
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 0, roundLimit: 8))
        guard case .pending = runtime.resolveLazyListTarget(target) else {
            XCTFail("An unmounted logical row must remain pending with no construction budget")
            return NavigationLifetimeRequest(runtime: runtime, receipt: receipt, target: target, events: events)
        }
        return NavigationLifetimeRequest(runtime: runtime, receipt: receipt, target: target, events: events)
    }

    func close() {
        runtime.stopRenderLifecycleCallbacks()
        source.close()
        runtime.cancelRenderLifecycleTasks()
        scroll.setChildren([])
    }
}

@MainActor
private final class NavigationLifetimeLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { NavigationLifetimeEpoch() }
}

@MainActor
private final class NavigationLifetimeEpoch: RetainedBuildEpoch {
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
