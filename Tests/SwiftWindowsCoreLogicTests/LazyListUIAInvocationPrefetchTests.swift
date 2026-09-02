import CUIAInterop
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Actual public List/Button Invoke completion. Setup may realize a far row;
/// every result below is checked before any later layout, snapshot, or Focus.
@MainActor
final class LazyListUIAInvocationPrefetchTests: XCTestCase {
    func testFarRequiredInvokeSettlesWithinItsOriginalFourRoundsWithoutOptionalNeighbors() async throws {
        let fixture = try InvocationPrefetchFixture(target: 300)
        defer { fixture.close() }
        let required = fixture.requiredRows().map(\.id)
        XCTAssertEqual(required, [298, 299, 300])
        let optional = try XCTUnwrap(fixture.adapter.logicalToken(after: fixture.originalItem.token))
        fixture.arm()

        XCTAssertEqual(SWU_UIAProviderInvokeResult(fixture.invokePattern), 0)

        assertSuccessfulInvoke(fixture)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertEqual(Set(fixture.probe.postCalls.map(\.id)), Set(required + [297]))
        XCTAssertFalse(fixture.probe.postCalls.contains { $0.id == 301 })
        XCTAssertNil(fixture.adapter.mountedNodes(for: optional))
        XCTAssertNil(fixture.adapter.knownLeafCount(for: optional))
        let bounds = try XCTUnwrap(fixture.adapter.logicalBounds(for: optional))
        let window = try XCTUnwrap(fixture.viewport())
        XCTAssertGreaterThanOrEqual(bounds.origin, window.maxY)
        XCTAssertLessThan(bounds.origin, window.maxY + 64, "Row301 is within even the minimum ordinary prefetch")
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .complete)
        XCTAssertNil(fixture.runtime.focusedNode)
    }

    func testTargetThatBecomesOptionalUsesTheCurrentSelectionAndOrdinaryPrefetch() async throws {
        // This is an ordinary-planning control, not a claim about default4.
        // Moving in the action precedes capture of the completion's scroll proof.
        let fixture = try InvocationPrefetchFixture(target: 0)
        defer { fixture.close() }
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: 16))
        let originalRequired = Set(fixture.requiredRows().map(\.id))
        let originalBounds = try XCTUnwrap(fixture.adapter.logicalBounds(for: fixture.originalItem.token))
        let oldWindow = try XCTUnwrap(fixture.viewport())
        let nextOffset =
            fixture.scroll.scrollOffset + originalBounds.origin + originalBounds.extent - oldWindow.minY + 1
        fixture.onAction = { fixture in fixture.scroll.scrollOffset = nextOffset }
        fixture.arm()

        XCTAssertEqual(SWU_UIAProviderInvokeResult(fixture.invokePattern), 0)

        assertSuccessfulInvoke(fixture, roundLimit: 16)
        XCTAssertEqual(fixture.scroll.scrollOffset, nextOffset)
        let window = try XCTUnwrap(fixture.viewport())
        let target = try XCTUnwrap(fixture.adapter.logicalBounds(for: fixture.originalItem.token))
        XCTAssertLessThan(target.origin + target.extent, window.minY)
        XCTAssertLessThan(window.minY - target.origin - target.extent, 64)
        XCTAssertFalse(fixture.requiredRows().contains { $0.id == 0 })
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: fixture.originalItem.token), 2)
        XCTAssertTrue(fixture.probe.postCalls.contains { $0.id == 0 })
        let newlyRequired = try XCTUnwrap(fixture.requiredRows().first { !originalRequired.contains($0.id) })
        let requiredCall = try XCTUnwrap(fixture.probe.postCalls.first { $0.id == newlyRequired.id })
        let transitionCall = try XCTUnwrap(fixture.probe.postCalls.first { $0.id == 0 })
        XCTAssertGreaterThan(requiredCall.round, transitionCall.round)
        let optional = try XCTUnwrap(
            fixture.mountedRows().first {
                $0.origin >= window.maxY && $0.origin < window.maxY + 64 && !originalRequired.contains($0.id)
            })
        XCTAssertEqual(optional.measuredLeaves, 2)
        let optionalCall = try XCTUnwrap(fixture.probe.postCalls.first { $0.id == optional.id })
        XCTAssertEqual(optionalCall.round, requiredCall.round)
        XCTAssertEqual(optionalCall.sequence, requiredCall.sequence)
        XCTAssertGreaterThan(optionalCall.id, newlyRequired.id, "This is trailing prefetch, not a leading gap probe")
        XCTAssertTrue(fixture.adoptions.contains { $0.physical == ObjectIdentifier(optionalCall.physical) })
        XCTAssertNil(fixture.runtime.focusedNode)
    }

    func testRequiredUnknownPredecessorIsActuallyAdoptedAndRetiredDuringInvokeCompletion() async throws {
        let fixture = try InvocationPrefetchFixture(target: 300)
        defer { fixture.close() }
        let firstRequired = try XCTUnwrap(fixture.requiredRows().first)
        XCTAssertEqual(firstRequired.id, 298)
        let probeID = firstRequired.id - 1
        fixture.arm()

        XCTAssertEqual(SWU_UIAProviderInvokeResult(fixture.invokePattern), 0)

        assertSuccessfulInvoke(fixture)
        let required = try XCTUnwrap(fixture.probe.postCalls.first { $0.id == firstRequired.id })
        let probe = try XCTUnwrap(fixture.probe.postCalls.first { $0.id == probeID })
        XCTAssertEqual(required.round, 2)
        XCTAssertEqual(probe.round, 3)
        XCTAssertEqual(probe.sequence, required.sequence)
        let adopted = try XCTUnwrap(fixture.adoptions.first { $0.physical == ObjectIdentifier(probe.physical) })
        XCTAssertEqual(adopted.round, probe.round)
        XCTAssertGreaterThan(adopted.pass, probe.pass)
        XCTAssertTrue(
            fixture.trace.contains { $0.kind == .measurementPhase && $0.consumedRounds == probe.round + 1 })
        // A leading gap with an unknown predecessor cannot acquire this
        // measurement. The probe's accepted boundary, not its own height,
        // makes the required record measurable in the following paid round.
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: firstRequired.token), 2)
        XCTAssertNil(fixture.adapter.mountedNodes(for: probe.token))
        XCTAssertEqual(probe.physical.state, .revoked)
        XCTAssertFalse(probe.physical.actualAttachments.contains(where: \.isAttached))
        XCTAssertFalse(fixture.mountedRows().contains { $0.id == probeID })
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
    }

    func testElementExhaustionAfterCompletionStartsDoesNotGrantAnotherQuery() async throws {
        let fixture = try InvocationPrefetchFixture(target: 300)
        defer { fixture.close() }
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 2, roundLimit: 4))
        fixture.arm()

        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: fixture.element))

        XCTAssertEqual(fixture.probe.activations, [300])
        XCTAssertEqual(fixture.probe.postCalls.count, 2)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 2)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .budgetExhausted)
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertNil(fixture.adapter.knownLeafCount(for: fixture.originalItem.token))
        let boundary = try XCTUnwrap(fixture.effectBoundary)
        XCTAssertTrue(fixture.probe.postCalls.allSatisfy { $0.pass > boundary.pass && $0.round > 1 })
        XCTAssertTrue(fixture.trace.contains { $0.kind == .providerPhase && $0.consumedRounds > 1 })
        assertSharedBudget(fixture, elementLimit: 2)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        XCTAssertFalse(fixture.probe.postCalls.contains { $0.physical.state == .provisional })
        if case .settled(let receipt) = fixture.runtime.layoutSettlementStatus {
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
        }
    }

    func testSiblingAdapterPerformsItsOwnOrdinaryOptionalWorkInTheCompletionQuery() async throws {
        // The sibling deliberately needs a larger ordinary convergence scope;
        // it must not inherit the target's omission merely by sharing a runtime.
        let fixture = try InvocationPrefetchFixture(target: 0, hasSibling: true)
        defer { fixture.close() }
        let sibling = try XCTUnwrap(fixture.sibling)
        let siblingList = try XCTUnwrap(fixture.siblingList)
        let siblingScroll = try XCTUnwrap(fixture.siblingScroll)
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: 16))
        let oldRequired = Set(fixture.requiredRows(in: siblingList, probe: sibling).map(\.id))
        let oldWindow = try XCTUnwrap(fixture.viewport(in: siblingList))
        let tail = try XCTUnwrap(fixture.requiredRows(in: siblingList, probe: sibling).last)
        let nextOffset = siblingScroll.scrollOffset + tail.origin - oldWindow.minY
        let primaryOffset = fixture.scroll.scrollOffset
        fixture.onAction = { _ in siblingScroll.scrollOffset = nextOffset }
        fixture.arm()

        XCTAssertEqual(SWU_UIAProviderInvokeResult(fixture.invokePattern), 0)

        assertSuccessfulInvoke(fixture, roundLimit: 16)
        XCTAssertEqual(fixture.scroll.scrollOffset, primaryOffset)
        XCTAssertEqual(siblingScroll.scrollOffset, nextOffset)
        let siblingAdapter = try XCTUnwrap(siblingList.retainedLazyListAdapter)
        XCTAssertFalse(siblingAdapter.hasUnresolvedWork)
        let window = try XCTUnwrap(fixture.viewport(in: siblingList))
        let required = try XCTUnwrap(
            fixture.requiredRows(in: siblingList, probe: sibling).first { !oldRequired.contains($0.id) })
        XCTAssertTrue(sibling.postCalls.contains { $0.id == required.id })
        let optional = try XCTUnwrap(
            fixture.mountedRows(in: siblingList, probe: sibling).first {
                $0.origin >= window.maxY && $0.origin < window.maxY + 64 && !oldRequired.contains($0.id)
            })
        XCTAssertEqual(optional.measuredLeaves, 2)
        let siblingCall = try XCTUnwrap(sibling.postCalls.first { $0.id == optional.id })
        let primaryCall = try XCTUnwrap(fixture.probe.postCalls.first)
        XCTAssertEqual(siblingCall.sequence, primaryCall.sequence)
        XCTAssertGreaterThan(siblingCall.round, primaryCall.round)
        XCTAssertTrue(fixture.adoptions.contains { $0.physical == ObjectIdentifier(siblingCall.physical) })
        XCTAssertTrue(sibling.activations.isEmpty)
    }

    func testLaterIndependentRequiredViewportChangeRestoresOrdinaryPrefetch() async throws {
        let fixture = try InvocationPrefetchFixture(target: 300)
        defer { fixture.close() }
        let nextToken = try XCTUnwrap(fixture.adapter.logicalToken(after: fixture.originalItem.token))
        fixture.arm()

        XCTAssertEqual(SWU_UIAProviderInvokeResult(fixture.invokePattern), 0)

        // All original-call evidence is closed before the independent control.
        assertSuccessfulInvoke(fixture)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertNil(fixture.adapter.mountedNodes(for: nextToken))
        let originalCalls = fixture.probe.calls.count
        let next = try XCTUnwrap(fixture.adapter.logicalBounds(for: nextToken))
        let window = try XCTUnwrap(fixture.viewport())
        let nextOffset = fixture.scroll.scrollOffset + next.origin - window.minY
        fixture.probe.afterEffect = false
        fixture.runtime.recordsLazyListUIAPhasesForTesting = true
        fixture.scroll.scrollOffset = nextOffset

        XCTAssertNotNil(fixture.host.layout())

        assertSettled(fixture.runtime)
        let ordinary = Array(fixture.probe.calls.dropFirst(originalCalls))
        XCTAssertTrue(ordinary.contains { $0.id == 301 })
        XCTAssertTrue(ordinary.allSatisfy { !$0.afterEffect })
        let ordinaryWindow = try XCTUnwrap(fixture.viewport())
        XCTAssertTrue(fixture.requiredRows().contains { $0.id == 301 })
        let optional = try XCTUnwrap(fixture.mountedRows().first { $0.origin >= ordinaryWindow.maxY })
        XCTAssertEqual(optional.measuredLeaves, 2)
        XCTAssertTrue(ordinary.contains { $0.id == optional.id })
        XCTAssertGreaterThan(optional.id, 301)
        XCTAssertEqual(fixture.probe.activations, [300])
        assertSharedBudget(fixture, queries: 1)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
    }

    func testScrollABADuringTheFirstCompletionFactoryStopsLaterFactoriesAndCleansUp() async throws {
        let fixture = try InvocationPrefetchFixture(target: 300)
        defer { fixture.close() }
        let offset = fixture.scroll.scrollOffset
        var interventions = 0
        fixture.onFirstPostFactory = { fixture in
            interventions += 1
            fixture.scroll.scrollOffset = offset + 1
            fixture.scroll.scrollOffset = offset
        }
        fixture.arm()

        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: fixture.element))

        XCTAssertEqual(interventions, 1)
        XCTAssertEqual(fixture.probe.activations, [300])
        XCTAssertEqual(fixture.probe.postCalls.count, 1)
        XCTAssertEqual(fixture.scroll.scrollOffset, offset)
        XCTAssertNotNil(fixture.originalButton)
        XCTAssertTrue(fixture.currentButton === fixture.originalButton)
        let rejected = try XCTUnwrap(fixture.probe.postCalls.first)
        XCTAssertEqual(rejected.physical.state, .revoked)
        XCTAssertFalse(rejected.physical.actualAttachments.contains(where: \.isAttached))
        XCTAssertFalse(fixture.adoptions.contains { $0.physical == ObjectIdentifier(rejected.physical) })
        assertSharedBudget(fixture)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        XCTAssertNil(fixture.runtime.focusedNode)
    }

    func testAReplacementAdapterCannotReuseTheOriginalCompletionToken() async throws {
        let fixture = try InvocationPrefetchFixture(target: 300)
        defer { fixture.close() }
        var interventions = 0
        var entered: ObjectIdentifier?
        fixture.onFirstPostFactory = { fixture in
            interventions += 1
            entered = ObjectIdentifier(fixture.adapter)
            fixture.host.reload()
        }
        fixture.arm()

        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: fixture.element))

        XCTAssertEqual(interventions, 1)
        XCTAssertNotNil(entered)
        XCTAssertNotEqual(ObjectIdentifier(fixture.adapter), entered)
        XCTAssertEqual(fixture.probe.activations, [300])
        XCTAssertEqual(fixture.probe.postCalls.count, 1)
        XCTAssertNil(fixture.runtime.lazyListAccessibilityGeneration(for: fixture.originalItem))
        let rejected = try XCTUnwrap(fixture.probe.postCalls.first)
        XCTAssertEqual(rejected.physical.state, .revoked)
        XCTAssertFalse(rejected.physical.actualAttachments.contains(where: \.isAttached))
        XCTAssertFalse(fixture.adoptions.contains { $0.physical == ObjectIdentifier(rejected.physical) })
        assertSharedBudget(fixture)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        XCTAssertNil(fixture.runtime.focusedNode)
    }

    private func assertSuccessfulInvoke(
        _ fixture: InvocationPrefetchFixture, roundLimit: Int = 4,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(fixture.probe.activations, [fixture.target], file: file, line: line)
        XCTAssertFalse(fixture.probe.postCalls.isEmpty, file: file, line: line)
        XCTAssertNotNil(fixture.originalButton, file: file, line: line)
        XCTAssertTrue(fixture.currentButton === fixture.originalButton, file: file, line: line)
        XCTAssertTrue(
            fixture.originalButton?.isRetainedLazyListAttached(in: fixture.runtime) == true, file: file, line: line)
        XCTAssertEqual(
            fixture.source.uiaLogicalItemState(elementID: fixture.element), .ordinary, file: file, line: line)
        XCTAssertNotNil(
            fixture.runtime.lazyListAccessibilityGeneration(for: fixture.originalItem), file: file, line: line)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork, file: file, line: line)
        XCTAssertFalse(fixture.requiredRows().isEmpty, file: file, line: line)
        for row in fixture.requiredRows() {
            XCTAssertEqual(row.measuredLeaves, 2, file: file, line: line)
        }
        assertSettled(fixture.runtime, file: file, line: line)
        assertSharedBudget(fixture, roundLimit: roundLimit, file: file, line: line)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild, file: file, line: line)
    }

    private func assertSettled(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            return XCTFail("Expected this query's completed layout receipt", file: file, line: line)
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
    }

    private func assertSharedBudget(
        _ fixture: InvocationPrefetchFixture, elementLimit: Int = 128, roundLimit: Int = 4, queries: Int = 2,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let trace = fixture.trace
        let rounds = fixture.runtime.lastLazyListConsumedRounds
        let elements = fixture.runtime.lastLazyListConsumedElements
        XCTAssertGreaterThan(rounds, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(rounds, roundLimit, file: file, line: line)
        XCTAssertGreaterThanOrEqual(elements, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(elements, elementLimit, file: file, line: line)
        XCTAssertEqual(
            trace.filter { $0.kind == .roundDebit }.map(\.consumedRounds), Array(1..<(rounds + 1)),
            file: file, line: line)
        XCTAssertEqual(
            Set(trace.filter { $0.kind == .layoutPass }.map(\.resolutionSequence)).count, queries, file: file,
            line: line)
        XCTAssertFalse(
            trace.contains { $0.kind == .ownedScroll || $0.kind == .resumedProviderPhase }, file: file, line: line)
        for (previous, current) in zip(trace, trace.dropFirst()) {
            XCTAssertGreaterThanOrEqual(current.consumedRounds, previous.consumedRounds, file: file, line: line)
            XCTAssertLessThanOrEqual(current.remainingElements, previous.remainingElements, file: file, line: line)
            XCTAssertLessThanOrEqual(current.remainingRounds, previous.remainingRounds, file: file, line: line)
        }
    }
}

@MainActor
private struct InvocationPrefetchFactoryCall {
    let id: Int
    let token: RetainedLazyListRowToken
    let physical: RetainedLazyListPhysicalActivityReceipt
    let afterEffect: Bool
    let round: Int
    let sequence: UInt64
    let pass: UInt64
}

private struct InvocationPrefetchAdoption {
    let physical: ObjectIdentifier
    let round: Int
    let pass: UInt64
}

private struct InvocationPrefetchRowInfo {
    let id: Int
    let token: RetainedLazyListRowToken
    let origin: Double
    let extent: Double
    let measuredLeaves: Int?
}

@MainActor
private final class InvocationPrefetchProbe {
    let lane: String
    let rows = Array(0..<1000)
    weak var runtime: RetainedViewRuntime?
    var calls: [InvocationPrefetchFactoryCall] = []
    var activations: [Int] = []
    var afterEffect = false
    var onAction: ((Int) -> Void)?
    var onFactory: ((InvocationPrefetchFactoryCall) -> Void)?

    init(lane: String) { self.lane = lane }
    var postCalls: [InvocationPrefetchFactoryCall] { calls.filter(\.afterEffect) }
    func identifier(_ id: Int) -> String { "invoke.prefetch.\(lane).\(id)" }

    func makeRows(_ id: Int) -> [AnyView] {
        guard let native = ViewBuildContextScope.current?.viewIdentity.lazyList?.native else {
            XCTFail("The public factory must have its real managed row attribution")
            return []
        }
        let phase = runtime?.lazyListUIAPhasesForTesting.last
        let call = InvocationPrefetchFactoryCall(
            id: id, token: native.rowRequest.token, physical: native.physical, afterEffect: afterEffect,
            round: phase?.consumedRounds ?? 0, sequence: phase?.resolutionSequence ?? 0,
            pass: runtime?.layoutPassID ?? 0)
        calls.append(call)
        onFactory?(call)
        return [
            AnyView(
                Button("Prefetch \(lane) \(id)") { [weak self] in
                    guard let self else { return }
                    self.activations.append(id)
                    self.onAction?(id)
                }
                .accessibilityIdentifier(identifier(id))
                .frame(height: 24))
        ]
    }
}

@MainActor
private final class InvocationPrefetchFixture {
    struct EffectBoundary {
        let pass: UInt64
    }

    let target: Int
    let probe: InvocationPrefetchProbe
    let sibling: InvocationPrefetchProbe?
    let host: MountedLazyListTestHost
    let source: RuntimeUIAElementTreeSource
    let bridge: UIAProviderBridge
    let list: ViewNode
    let scroll: ViewNode
    let siblingList: ViewNode?
    let siblingScroll: ViewNode?
    let originalItem: RetainedLazyListAccessibilityItem
    private(set) weak var originalButton: ViewNode?
    let row: UnsafeMutableRawPointer
    let invokePattern: UnsafeMutableRawPointer
    let element: UInt64
    private let rootProvider: UnsafeMutableRawPointer
    private var closed = false
    private(set) var effectBoundary: EffectBoundary?
    private(set) var adoptions: [InvocationPrefetchAdoption] = []
    var onAction: ((InvocationPrefetchFixture) -> Void)?
    var onFirstPostFactory: ((InvocationPrefetchFixture) -> Void)?

    var runtime: RetainedViewRuntime { host.runtime }
    var adapter: RetainedLazyListRuntimeAdapter { list.retainedLazyListAdapter! }
    var trace: [RetainedViewRuntime.LazyListUIAPhaseTrace] { runtime.lazyListUIAPhasesForTesting }
    var currentButton: ViewNode? {
        host.nodes.first { $0.accessibilityIdentifier == probe.identifier(target) && $0.onActivate != nil }
    }

    init(target: Int, hasSibling: Bool = false) throws {
        self.target = target
        let probe = InvocationPrefetchProbe(lane: "primary")
        let sibling = hasSibling ? InvocationPrefetchProbe(lane: "sibling") : nil
        self.probe = probe
        self.sibling = sibling
        let host = MountedLazyListTestHost(size: Size(width: hasSibling ? 640 : 320, height: 80)) {
            if let sibling {
                return AnyView(
                    HStack(spacing: 0) {
                        List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain)
                        List(sibling.rows, id: \.self) { sibling.makeRows($0) }.listStyle(.plain)
                    })
            }
            return AnyView(List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain))
        }
        self.host = host
        probe.runtime = host.runtime
        sibling?.runtime = host.runtime
        let source = RuntimeUIAElementTreeSource(runtime: host.runtime)
        self.source = source
        let bridge = UIAProviderBridge(source: source)
        self.bridge = bridge
        var ownedRoot: UnsafeMutableRawPointer?
        var ownedRow: UnsafeMutableRawPointer?
        var ownedInvoke: UnsafeMutableRawPointer?
        do {
            XCTAssertNotNil(host.layout())
            let root = try XCTUnwrap(bridge.retainedRootProviderForTesting())
            ownedRoot = root
            let container = try XCTUnwrap(Self.findItemContainer(in: root))
            defer { SWU_UIAReleaseProvider(container) }
            for _ in 0...target {
                let previous = ownedRow
                ownedRow = nil
                defer { SWU_UIAReleaseProvider(previous) }
                XCTAssertEqual(
                    SWU_UIAItemContainerProviderFindItemResult(
                        container, previous, Int32(SWU_UIA_ITEM_PROPERTY_ANY), nil, 0, &ownedRow), 0)
            }
            let row = try XCTUnwrap(ownedRow)
            if target > 0 {
                let virtual = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(row))
                defer { SWU_UIAReleaseProvider(virtual) }
                XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(virtual), 0)
            }
            let invoke = try XCTUnwrap(SWU_UIAProviderGetInvokePattern(row))
            ownedInvoke = invoke
            let element = try Self.elementID(row)
            let button = try XCTUnwrap(
                host.nodes.first { $0.accessibilityIdentifier == probe.identifier(target) && $0.onActivate != nil })
            let list = try XCTUnwrap(Self.listAncestor(of: button))
            let scroll = try XCTUnwrap(Self.scrollAncestor(of: list))
            let item = try XCTUnwrap(host.runtime.lazyListAccessibilityItem(in: list, containing: button))
            self.rootProvider = root
            self.row = row
            self.invokePattern = invoke
            self.element = element
            self.list = list
            self.scroll = scroll
            self.originalItem = item
            self.originalButton = button
            if let sibling {
                let siblingButton = try XCTUnwrap(host.find(sibling.identifier(0)))
                let siblingList = try XCTUnwrap(Self.listAncestor(of: siblingButton))
                self.siblingList = siblingList
                self.siblingScroll = try XCTUnwrap(Self.scrollAncestor(of: siblingList))
                XCTAssertFalse(siblingList === list)
            } else {
                self.siblingList = nil
                self.siblingScroll = nil
            }
        } catch {
            SWU_UIAReleaseProvider(ownedInvoke)
            SWU_UIAReleaseProvider(ownedRow)
            SWU_UIAReleaseProvider(ownedRoot)
            host.close()
            throw error
        }
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            close()
            throw InvocationPrefetchFixtureError.unsettledSetup
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint)
        XCTAssertEqual(source.uiaLogicalItemState(elementID: element), .ordinary)
        XCTAssertNil(runtime.focusedNode)
        probe.onAction = { [weak self] id in
            guard let self else { return }
            XCTAssertEqual(id, self.target)
            XCTAssertNil(self.effectBoundary, "The original effect runs once")
            self.effectBoundary = EffectBoundary(pass: self.runtime.layoutPassID)
            self.probe.afterEffect = true
            self.sibling?.afterEffect = true
            self.onAction?(self)
        }
        probe.onFactory = { [weak self] call in
            guard let self, call.afterEffect, self.probe.postCalls.count == 1 else { return }
            self.onFirstPostFactory?(self)
        }
        runtime.root.onLayout = { [weak self] _ in self?.recordAdoptions() }
    }

    func arm(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(probe.activations.isEmpty, file: file, line: line)
        XCTAssertNotNil(originalButton?.onActivate, file: file, line: line)
        XCTAssertTrue(runtime.isLazyListAccessibilityItemCurrent(originalItem), file: file, line: line)
        XCTAssertEqual(source.uiaLogicalItemState(elementID: element), .ordinary, file: file, line: line)
        runtime.recordsLazyListUIAPhasesForTesting = true
    }

    /// The same parent-relative native arithmetic as resolvedVirtualizationContext,
    /// without publishing its ancestor cache or descent stamps, or running layout.
    func viewport(in suppliedList: ViewNode? = nil) -> Rect? {
        var node: ViewNode? = suppliedList ?? list
        var y = 0.0
        while let current = node {
            if current.scrollAxis == .vertical {
                return Rect(
                    x: 0, y: current.resolvedScrollOffset - y,
                    width: current.resolvedFrame.width, height: current.resolvedFrame.height)
            }
            y += current.resolvedFrame.minY
            node = current.parent
        }
        return nil
    }

    func mountedRows(
        in suppliedList: ViewNode? = nil, probe suppliedProbe: InvocationPrefetchProbe? = nil
    ) -> [InvocationPrefetchRowInfo] {
        let list = suppliedList ?? self.list
        let probe = suppliedProbe ?? self.probe
        guard let adapter = list.retainedLazyListAdapter else { return [] }
        var seen: Set<Int> = []
        var rows: [InvocationPrefetchRowInfo] = []
        for call in probe.calls.reversed() where seen.insert(call.id).inserted {
            guard adapter.mountedNodes(for: call.token)?.isEmpty == false,
                let bounds = adapter.logicalBounds(for: call.token)
            else { continue }
            rows.append(
                InvocationPrefetchRowInfo(
                    id: call.id, token: call.token, origin: bounds.origin, extent: bounds.extent,
                    measuredLeaves: adapter.knownLeafCount(for: call.token)))
        }
        return rows.sorted { $0.id < $1.id }
    }

    func requiredRows(
        in suppliedList: ViewNode? = nil, probe suppliedProbe: InvocationPrefetchProbe? = nil
    ) -> [InvocationPrefetchRowInfo] {
        guard let window = viewport(in: suppliedList) else { return [] }
        // These fixtures have no focus/pointer pins, explicit realization lease,
        // empty rows, transforms or headers. Only measured positive intervals
        // intersecting the ordinary viewport are required after settlement.
        return mountedRows(in: suppliedList, probe: suppliedProbe).filter {
            $0.origin < window.maxY && $0.origin + $0.extent > window.minY
        }
    }

    private func recordAdoptions() {
        guard let boundary = effectBoundary, runtime.layoutPassID > boundary.pass else { return }
        let calls = probe.postCalls + (sibling?.postCalls ?? [])
        for call in calls
        where call.physical.state == .active && call.physical.actualAttachments.contains(where: \.isAttached) {
            let id = ObjectIdentifier(call.physical)
            if !adoptions.contains(where: { $0.physical == id }) {
                adoptions.append(
                    InvocationPrefetchAdoption(
                        physical: id, round: trace.last?.consumedRounds ?? 0, pass: runtime.layoutPassID))
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        onAction = nil
        onFirstPostFactory = nil
        probe.onAction = nil
        probe.onFactory = nil
        sibling?.onAction = nil
        sibling?.onFactory = nil
        runtime.root.onLayout = nil
        host.close()
        SWU_UIAReleaseProvider(invokePattern)
        SWU_UIAReleaseProvider(row)
        SWU_UIAReleaseProvider(rootProvider)
    }

    private static func listAncestor(of node: ViewNode) -> ViewNode? {
        var current: ViewNode? = node
        while let node = current {
            if node.retainedLazyListAdapter != nil { return node }
            current = node.parent
        }
        return nil
    }

    private static func scrollAncestor(of node: ViewNode) -> ViewNode? {
        var current = node.parent
        while let node = current {
            if node.scrollAxis == .vertical { return node }
            current = node.parent
        }
        return nil
    }

    private static func elementID(_ provider: UnsafeMutableRawPointer) throws -> UInt64 {
        var values = [Int32](repeating: 0, count: 8)
        var count: Int32 = 0
        let result = values.withUnsafeMutableBufferPointer {
            SWU_UIAProviderGetRuntimeIdResult(provider, $0.baseAddress, Int32($0.count), &count)
        }
        XCTAssertEqual(result, 0)
        XCTAssertGreaterThanOrEqual(count, 2)
        let low = UInt64(UInt32(bitPattern: try XCTUnwrap(values.prefix(Int(max(0, count))).dropFirst().first)))
        let high = count > 2 ? UInt64(UInt32(bitPattern: values[2])) << 32 : 0
        return low | high
    }

    private static func findItemContainer(in provider: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
        if let pattern = SWU_UIAProviderGetItemContainerPattern(provider) { return pattern }
        var next = SWU_UIAProviderNavigate(provider, Int32(SWU_UIA_NAV_FIRST_CHILD))
        while let child = next {
            let pattern = findItemContainer(in: child)
            next = pattern == nil ? SWU_UIAProviderNavigate(child, Int32(SWU_UIA_NAV_NEXT_SIBLING)) : nil
            SWU_UIAReleaseProvider(child)
            if let pattern { return pattern }
        }
        return nil
    }
}

private enum InvocationPrefetchFixtureError: Error { case unsettledSetup }
