import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Suppression cases enter through real typed Runtime requests. No test supplies
/// the internal flag or changes an existing budget oracle. The public Button
/// case also needs the separately reviewed visibility fix.
@MainActor
final class LazyListUIAFinalPrefetchTests: XCTestCase {
    func testTypedRawFinalQueryOmitsOptionalRowsWithinTheDefaultBudget() async throws {
        let fixture = try FinalPrefetchRawFixture()
        defer { fixture.close() }
        XCTAssertEqual(fixture.primary.rowIDs, Array(0...6))
        XCTAssertFalse(fixture.probe.factories.contains(300))

        try fixture.withRequest { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            assertResolved(roots, request: request, fixture: fixture)
            XCTAssertEqual(fixture.primary.rowIDs, [298, 299, 300])
            XCTAssertTrue(fixture.probe.finalFactories.isEmpty)
            XCTAssertFalse(fixture.probe.finalEvents(of: .begin).isEmpty)
            XCTAssertFalse(fixture.probe.finalEvents(of: .commit).isEmpty)
            XCTAssertTrue(fixture.probe.factories.contains(298))
            XCTAssertTrue(fixture.probe.factories.contains(299))
            XCTAssertEqual(fixture.probe.factories.filter { $0 == 300 }.count, 1)
        }

        assertPaidTrace(fixture.runtime, maximumRounds: 4)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 128)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .complete)
        fixture.probe.assertClosedEpochs()
    }

    func testNextActualOrdinaryBuildRestoresOptionalPrefetch() async throws {
        let fixture = try FinalPrefetchRawFixture()
        defer { fixture.close() }
        try fixture.withRequest { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            assertResolved(roots, request: request, fixture: fixture)
        }
        XCTAssertEqual(fixture.primary.rowIDs, [298, 299, 300])
        XCTAssertFalse(fixture.primary.rowIDs.contains(301))
        let oldTrace = fixture.runtime.lazyListUIAPhasesForTesting
        let calls = fixture.probe.calls.count
        let offset = fixture.scroll.scrollOffset

        // Missing optional rows alone do not require work. This new ordinary
        // viewport introduces required row301 and therefore really builds.
        fixture.runtime.recordsLazyListUIAPhasesForTesting = true
        fixture.scroll.scrollOffset = offset + 20
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.scroll))

        assertSettled(fixture.runtime)
        let ordinary = Array(fixture.probe.calls.dropFirst(calls))
        XCTAssertTrue(ordinary.contains { $0.id == 301 })
        XCTAssertTrue(ordinary.contains { $0.id > 301 })
        XCTAssertTrue(ordinary.allSatisfy { !$0.afterOwnedScroll })
        XCTAssertTrue(fixture.primary.rowIDs.contains { $0 > 301 })
        XCTAssertEqual(
            fixture.runtime.lazyListUIAPhasesForTesting.first { $0.kind == .roundDebit }?.consumedRounds, 1)
        XCTAssertFalse(fixture.runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll })
        XCTAssertFalse(fixture.runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .resumedProviderPhase })
        XCTAssertEqual(oldTrace.filter { $0.kind == .ownedScroll }.count, 1)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        fixture.probe.assertClosedEpochs()
    }

    func testInitialTypedPreparationKeepsOrdinaryOptionalPrefetch() async throws {
        let fixture = try FinalPrefetchRawFixture()
        defer { fixture.close() }
        let calls = fixture.probe.calls.count
        fixture.scroll.scrollOffset = 120

        try fixture.withRequest { _ in
            XCTAssertEqual(fixture.scroll.scrollOffset, 120)
            XCTAssertTrue(fixture.primary.rowIDs.contains(6))
            XCTAssertTrue(fixture.primary.rowIDs.contains(8))
            XCTAssertTrue(fixture.primary.rowIDs.contains { $0 > 8 })
            XCTAssertTrue(fixture.probe.calls.dropFirst(calls).contains { $0.id > 8 })
            XCTAssertFalse(fixture.probe.factories.contains(300))
            XCTAssertFalse(fixture.runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll })
            XCTAssertFalse(fixture.runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .resumedProviderPhase })
            assertSettled(fixture.runtime)
        }
        fixture.probe.assertClosedEpochs()
    }

    func testGenericAccessibilityRealizationKeepsItsOrdinaryPrefetch() async throws {
        let fixture = try FinalPrefetchRawFixture(roundLimit: 16)
        defer { fixture.close() }
        let witness = try fixture.target()
        let mutation = try XCTUnwrap(fixture.runtime.beginAccessibilityMutation())
        defer { fixture.runtime.endAccessibilityMutation(mutation) }
        fixture.runtime.recordsLazyListUIAPhasesForTesting = true

        try fixture.runtime.withLazyListResolutionBudget {
            let item = try XCTUnwrap(
                fixture.runtime.prepareLazyListAccessibilityTarget(
                    token: witness.token, in: witness, during: mutation))
            let roots = try XCTUnwrap(fixture.runtime.realizeLazyListAccessibilityItem(item, during: mutation))
            XCTAssertTrue(roots.contains { $0.dynamicContentIndex == 300 })
            assertSettled(fixture.runtime)
            XCTAssertTrue(fixture.probe.factories.contains { $0 > 300 })
            XCTAssertTrue(fixture.primary.rowIDs.contains { $0 > 300 })
            XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0)
        }

        XCTAssertFalse(fixture.runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll })
        XCTAssertFalse(fixture.runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .resumedProviderPhase })
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 16)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 128)
        fixture.probe.assertClosedEpochs()
    }

    func testSiblingAdapterKeepsOrdinaryPrefetchDuringTheTargetFinalQuery() async throws {
        // Both columns share the same vertical scroll, so the owned reveal
        // actually exposes new required rows in the unrelated second adapter.
        let fixture = try FinalPrefetchRawFixture(hasSibling: true, roundLimit: 16)
        defer { fixture.close() }
        let sibling = try XCTUnwrap(fixture.sibling)
        XCTAssertEqual(sibling.rowIDs, Array(0...6))
        XCTAssertFalse(sibling.probe.factories.contains(300))

        try fixture.withRequest { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            assertResolved(roots, request: request, fixture: fixture)
            XCTAssertEqual(fixture.primary.rowIDs, [298, 299, 300])
            XCTAssertTrue(fixture.probe.finalFactories.isEmpty)
            XCTAssertFalse(sibling.probe.finalEvents(of: .begin).isEmpty)
            XCTAssertTrue(sibling.probe.finalFactories.contains { $0.id > 300 })
            XCTAssertTrue(sibling.rowIDs.contains { $0 > 300 })
            XCTAssertTrue(sibling.rowIDs.contains(300))
        }

        assertPaidTrace(fixture.runtime, maximumRounds: 16)
        fixture.probe.assertClosedEpochs()
        sibling.probe.assertClosedEpochs()
    }

    func testFocusedRequiredRowIsNotOmittedWithOptionalRows() async throws {
        let fixture = try FinalPrefetchRawFixture(roundLimit: 16)
        defer { fixture.close() }
        let focused = try XCTUnwrap(fixture.primary.weakRow(0)?.node)
        focused.isFocusable = true
        focused.isFocusEnabled = true
        fixture.runtime.requestFocus(focused)
        XCTAssertTrue(fixture.runtime.focusedNode === focused)
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.scroll))

        try fixture.withRequest { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            assertResolved(roots, request: request, fixture: fixture)
            XCTAssertTrue(fixture.runtime.focusedNode === focused)
            XCTAssertTrue(fixture.list.children.contains { $0 === focused })
            XCTAssertEqual(fixture.primary.rowIDs, [0, 298, 299, 300])
            XCTAssertTrue(fixture.probe.finalFactories.isEmpty)
            XCTAssertFalse(fixture.probe.finalEvents(of: .begin).isEmpty)
        }
        XCTAssertLessThanOrEqual(fixture.adapter.mountedRecordCount, 16)
        XCTAssertLessThanOrEqual(fixture.adapter.mountedLeafCount, 32)
        fixture.probe.assertClosedEpochs()
    }

    func testRequiredGapProbeIsBuiltAndRetiredBeforeTheFinalProvider() async throws {
        let fixture = try FinalPrefetchRawFixture(hasGaps: true, roundLimit: 16)
        defer { fixture.close() }
        let state = FinalPrefetchHookState()
        fixture.probe.onCanBuild = { [weak fixture] in
            guard let fixture, fixture.probe.afterOwnedScroll, state.probeMountedAtFinal == nil else { return }
            state.probeMountedAtFinal = fixture.primary.rowIDs.contains(297)
        }

        try fixture.withRequest { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            assertResolved(roots, request: request, fixture: fixture)
            XCTAssertTrue(fixture.probe.calls.contains { $0.id == 297 && !$0.afterOwnedScroll })
            XCTAssertEqual(try XCTUnwrap(state.probeMountedAtFinal), false)
            XCTAssertTrue(fixture.probe.releases.contains { $0.id == 297 && !$0.afterOwnedScroll })
            XCTAssertTrue(fixture.list.children.contains { $0.retainedLazyListGap != nil })
            XCTAssertFalse(fixture.probe.finalEvents(of: .begin).isEmpty)
            XCTAssertTrue(fixture.probe.finalFactories.isEmpty)
            XCTAssertEqual(fixture.adapter.knownLeafCount(for: request.item.token), 2)
        }
        XCTAssertLessThanOrEqual(fixture.adapter.mountedRecordCount, 16)
        XCTAssertLessThanOrEqual(fixture.adapter.mountedLeafCount, 32)
        fixture.probe.assertClosedEpochs()
    }

    func testFullMountedMeasurementOracleStillRejectsAnotherRequiredLeaf() async throws {
        let fixture = try FinalPrefetchRawFixture()
        defer { fixture.close() }
        try fixture.withRequest { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            assertResolved(roots, request: request, fixture: fixture)
            // This raw fixture has no header, transform, or content/environment
            // revision publisher. Build the value from its actual stored layout
            // without invoking another query or accessing Runtime's private walk.
            XCTAssertTrue(fixture.list.parent === fixture.scroll)
            XCTAssertEqual(fixture.list.resolvedFrame.origin, .zero)
            let context = try XCTUnwrap(
                RetainedLazyListMeasurementContext(
                    width: fixture.list.resolvedFrame.width, displayScale: fixture.runtime.displayScale,
                    contentRevision: 0, environmentRevision: 0))
            let viewport = try XCTUnwrap(
                RetainedLazyListRuntimeAdapter.Viewport(
                    context: context, offset: fixture.scroll.resolvedScrollOffset,
                    extent: fixture.scroll.resolvedFrame.height))
            let measurements = try fixture.measurements()
            let calls = fixture.probe.calls.count
            let trace = fixture.runtime.lazyListUIAPhasesForTesting
            XCTAssertEqual(measurements.count, fixture.list.children.count)
            XCTAssertTrue(fixture.adapter.matchesAcceptedMeasurements(measurements, viewport: viewport))
            let neighbor = try XCTUnwrap(measurements.firstIndex { $0.node.dynamicContentIndex == 298 })
            XCTAssertNotEqual(measurements[neighbor].token, request.item.token)
            var wrong = measurements
            let original = wrong[neighbor]
            wrong[neighbor] = .init(
                token: original.token, leafIndex: original.leafIndex, node: original.node, extent: original.extent + 1)
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(wrong, viewport: viewport))
            wrong = measurements
            wrong.remove(at: neighbor)
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(wrong, viewport: viewport))
            XCTAssertEqual(fixture.probe.calls.count, calls)
            XCTAssertEqual(fixture.runtime.lazyListUIAPhasesForTesting.count, trace.count)
            XCTAssertTrue(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            assertSettled(fixture.runtime)
        }
    }

    func testFinishingRequestInFinalCanBuildStopsBeforeAnotherEpoch() async throws {
        let fixture = try FinalPrefetchRawFixture()
        defer { fixture.close() }
        let state = FinalPrefetchHookState()
        try fixture.withRequest { request in
            state.request = request
            fixture.probe.onCanBuild = { [weak fixture] in
                guard let fixture, fixture.probe.afterOwnedScroll, state.interventions == 0,
                    let request = state.request
                else { return }
                state.interventions += 1
                state.offset = fixture.scroll.scrollOffset
                state.factoriesAtHook = fixture.probe.calls.count
                fixture.runtime.finishLazyListUIARequest(request)
            }

            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertEqual(state.interventions, 1)
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.calls.count, try XCTUnwrap(state.factoriesAtHook))
            XCTAssertEqual(fixture.scroll.scrollOffset, try XCTUnwrap(state.offset))
            XCTAssertEqual(fixture.probe.finalEvents(of: .canBuild).count, 1)
            XCTAssertTrue(fixture.probe.finalEvents(of: .begin).isEmpty)
            XCTAssertEqual(fixture.runtime.lazyListUIAPhasesForTesting.filter { $0.kind == .ownedScroll }.count, 1)
        }
        XCTAssertNil(state.request)
        fixture.probe.assertClosedEpochs()
    }

    func testFinishingRequestInFinalCanAdoptStillAbandonsAndFinishesItsEpoch() async throws {
        let fixture = try FinalPrefetchRawFixture()
        defer { fixture.close() }
        let state = FinalPrefetchHookState()
        try fixture.withRequest { request in
            state.request = request
            fixture.probe.onCanAdopt = { [weak fixture] in
                guard let fixture, fixture.probe.afterOwnedScroll, state.interventions == 0,
                    let request = state.request
                else { return }
                state.interventions += 1
                state.offset = fixture.scroll.scrollOffset
                state.factoriesAtHook = fixture.probe.calls.count
                fixture.runtime.finishLazyListUIARequest(request)
            }

            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertEqual(state.interventions, 1)
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.calls.count, try XCTUnwrap(state.factoriesAtHook))
            XCTAssertEqual(fixture.scroll.scrollOffset, try XCTUnwrap(state.offset))
            XCTAssertEqual(fixture.probe.finalEvents(of: .begin).count, 1)
            XCTAssertEqual(fixture.probe.finalEvents(of: .abandon).count, 1)
            XCTAssertEqual(fixture.probe.finalEvents(of: .finish).count, 1)
            XCTAssertTrue(fixture.probe.finalEvents(of: .commit).isEmpty)
            XCTAssertEqual(fixture.runtime.lazyListUIAPhasesForTesting.filter { $0.kind == .ownedScroll }.count, 1)
        }
        XCTAssertNil(state.request)
        fixture.probe.assertClosedEpochs()
    }

    func testRestoredAttachmentInFinalCanBuildCannotReuseThePlanningDecision() async throws {
        let fixture = try FinalPrefetchRawFixture()
        defer { fixture.close() }
        let state = FinalPrefetchHookState()
        let parent = try XCTUnwrap(fixture.list.parent)
        XCTAssertEqual(parent.children.count, 1)
        fixture.probe.onCanBuild = { [weak fixture, weak parent] in
            guard let fixture, let parent, fixture.probe.afterOwnedScroll, state.interventions == 0 else { return }
            state.interventions += 1
            state.offset = fixture.scroll.scrollOffset
            state.factoriesAtHook = fixture.probe.calls.count
            parent.removeChild(fixture.list)
            parent.addChild(fixture.list)
        }

        try fixture.withRequest { request in
            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertEqual(state.interventions, 1)
            XCTAssertTrue(fixture.list.parent === parent)
            XCTAssertTrue(fixture.list.retainedLazyListRuntime === fixture.runtime)
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.calls.count, try XCTUnwrap(state.factoriesAtHook))
            XCTAssertEqual(fixture.scroll.scrollOffset, try XCTUnwrap(state.offset))
            XCTAssertTrue(fixture.probe.finalEvents(of: .begin).isEmpty)
            XCTAssertEqual(fixture.runtime.lazyListUIAPhasesForTesting.filter { $0.kind == .ownedScroll }.count, 1)
        }
        fixture.probe.assertClosedEpochs()
    }

    func testFinishedRequestAndEvictedOptionalRowsAreNotKeptAliveByTheFlag() async throws {
        let fixture = try FinalPrefetchRawFixture()
        defer { fixture.close() }
        let optional = try XCTUnwrap(fixture.primary.weakRow(6))
        XCTAssertNotNil(optional.node)
        let state = FinalPrefetchHookState()

        try fixture.withRequest { request in
            state.request = request
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            assertResolved(roots, request: request, fixture: fixture)
            XCTAssertFalse(fixture.primary.rowIDs.contains(6))
            XCTAssertNil(optional.node)
            XCTAssertTrue(fixture.probe.releases.contains { $0.id == 6 && $0.afterOwnedScroll })
        }

        XCTAssertNil(state.request)
        XCTAssertNil(optional.node)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
        fixture.probe.assertClosedEpochs()
    }

    func testPublicPendingReplacementDoesNotBuildOptionalFinalNeighbors() async throws {
        let probe = FinalPrefetchPublicProbe()
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(Array(0..<1000), id: \.self) { probe.makeRows($0) }.listStyle(.plain)
        }
        defer { host.close() }
        probe.runtime = host.runtime
        let source = RuntimeUIAElementTreeSource(runtime: host.runtime)
        XCTAssertNotNil(host.layout())
        let container = try XCTUnwrap(source.uiaElementSnapshots().first(where: \.supportsItemContainer)?.id)
        var element: UInt64?
        for _ in 0...300 {
            let next = source.uiaFindItem(containerID: container, afterElementID: element)
            guard case .item(let id) = next else {
                XCTFail("Expected the real logical row300 before pending replacement")
                return
            }
            element = id
        }
        let target = try XCTUnwrap(element)
        let identities = source.logicalItemIdentityCount
        host.reload()
        host.runtime.recordsLazyListUIAPhasesForTesting = true

        XCTAssertTrue(source.uiaRealizeVirtualizedItem(elementID: target))

        XCTAssertEqual(source.uiaLogicalItemState(elementID: target), .ordinary)
        XCTAssertEqual(source.logicalItemIdentityCount, identities)
        XCTAssertTrue(probe.calls.contains { $0.id == 300 && !$0.afterOwnedScroll })
        XCTAssertTrue(probe.calls.filter(\.afterOwnedScroll).isEmpty)
        XCTAssertTrue(probe.activations.isEmpty)
        XCTAssertEqual(host.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertLessThanOrEqual(host.runtime.lastLazyListConsumedElements, 128)
        XCTAssertEqual(host.runtime.lastLazyListWorkCompletion, .complete)
        assertPaidTrace(host.runtime, maximumRounds: 4)
        assertSettled(host.runtime)
    }

    private func assertResolved(
        _ roots: [ViewNode], request: RetainedLazyListUIARequest, fixture: FinalPrefetchRawFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            roots.contains { $0.dynamicContentIndex == 300 && $0.retainedLazyListGap == nil }, file: file, line: line)
        XCTAssertTrue(fixture.runtime.isResolvedLazyListUIARequestCurrent(request), file: file, line: line)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0, file: file, line: line)
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.scroll.resolvedScrollOffset, file: file, line: line)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild, file: file, line: line)
        XCTAssertTrue(fixture.probe.activations.isEmpty, file: file, line: line)
        assertSettled(fixture.runtime, file: file, line: line)
    }

    private func assertSettled(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            XCTFail("The query must return its own current measured settlement", file: file, line: line)
            return
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
    }

    private func assertPaidTrace(
        _ runtime: RetainedViewRuntime, maximumRounds: Int, file: StaticString = #filePath, line: UInt = #line
    ) {
        let trace = runtime.lazyListUIAPhasesForTesting
        let debits = trace.filter { $0.kind == .roundDebit }
        guard !debits.isEmpty else {
            XCTFail("Expected actual paid convergence rounds", file: file, line: line)
            return
        }
        XCTAssertEqual(debits.map(\.consumedRounds), Array(1...debits.count), file: file, line: line)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, debits.count, file: file, line: line)
        XCTAssertLessThanOrEqual(debits.count, maximumRounds, file: file, line: line)
        XCTAssertEqual(trace.filter { $0.kind == .ownedScroll }.count, 1, file: file, line: line)
        guard let owned = trace.firstIndex(where: { $0.kind == .ownedScroll }) else { return }
        let final = trace.dropFirst(owned + 1)
        XCTAssertTrue(final.contains { $0.kind == .measurementPhase }, file: file, line: line)
        XCTAssertTrue(final.contains { $0.kind == .providerPhase }, file: file, line: line)
        XCTAssertTrue(final.contains { $0.kind == .layoutPass }, file: file, line: line)
        for measurement in final where measurement.kind == .measurementPhase {
            XCTAssertTrue(debits.contains { $0.consumedRounds == measurement.consumedRounds }, file: file, line: line)
        }
    }
}

@MainActor
private final class FinalPrefetchRawFixture {
    let primary: FinalPrefetchLane
    let sibling: FinalPrefetchLane?
    let scroll: ViewNode
    let runtime: RetainedViewRuntime
    var probe: FinalPrefetchProbe { primary.probe }
    var list: ViewNode { primary.list }
    var adapter: RetainedLazyListRuntimeAdapter { primary.adapter }

    init(hasGaps: Bool = false, hasSibling: Bool = false, roundLimit: Int? = nil) throws {
        let primary = try FinalPrefetchLane(slot: 0, hasGaps: hasGaps)
        let sibling: FinalPrefetchLane?
        if hasSibling {
            sibling = try FinalPrefetchLane(slot: 1, hasGaps: false)
        } else {
            sibling = nil
        }
        let content: ViewNode
        if let sibling {
            content = ViewNode(
                layoutMode: .stack(.horizontal(spacing: 0, alignment: .leading, distribution: .fillEqually)),
                children: [primary.list, sibling.list])
        } else {
            content = primary.list
        }
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: hasSibling ? 240 : 120, height: 60), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)),
            scrollAxis: .vertical, children: [content])
        let runtime = RetainedViewRuntime(root: scroll)
        runtime.clock = { 0 }
        self.primary = primary
        self.sibling = sibling
        self.scroll = scroll
        self.runtime = runtime
        primary.probe.runtime = runtime
        sibling?.probe.runtime = runtime
        if let roundLimit {
            // Siblings, gap dependencies, and generic controls have an explicit
            // allowance; the plain typed and public cases use default4.
            XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: roundLimit))
        }
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: scroll))
        XCTAssertFalse(primary.adapter.hasUnresolvedWork)
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint)
        XCTAssertFalse(primary.probe.factories.contains(300))
        if let sibling { XCTAssertFalse(sibling.adapter.hasUnresolvedWork) }
    }

    func target() throws -> RetainedLazyListAccessibilityItem {
        let token = try XCTUnwrap(primary.source.token(for: .init(300)))
        return try XCTUnwrap(runtime.lazyListTarget(in: list, token: token))
    }

    @inline(never)
    func withRequest(_ body: @MainActor (RetainedLazyListUIARequest) throws -> Void) throws {
        let witness = try target()
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true
        try runtime.withLazyListResolutionBudget {
            let request = try XCTUnwrap(
                runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
            defer { runtime.finishLazyListUIARequest(request) }
            try body(request)
        }
    }

    func measurements() throws -> [RetainedLazyListRuntimeAdapter.Measurement] {
        try list.children.map { node in
            let token = try XCTUnwrap(adapter.mountedToken(containing: node))
            let roots = try XCTUnwrap(adapter.mountedNodes(for: token))
            let leaf = try XCTUnwrap(roots.firstIndex { $0 === node })
            return .init(
                token: token, leafIndex: leaf, node: node, extent: node.isHidden ? 0 : node.resolvedFrame.height)
        }
    }

    func close() {
        primary.probe.onCanBuild = nil
        primary.probe.onCanAdopt = nil
        sibling?.probe.onCanBuild = nil
        sibling?.probe.onCanAdopt = nil
        runtime.stopRenderLifecycleCallbacks()
        primary.source.close()
        sibling?.source.close()
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
private final class FinalPrefetchLane {
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let list: ViewNode
    let probe: FinalPrefetchProbe

    init(slot: Int, hasGaps: Bool) throws {
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        let probe = FinalPrefetchProbe()
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(slot)])
        let factory: @MainActor @Sendable (Int, RetainedViewIdentity) -> [ViewNode] = { id, prefix in
            probe.makeRows(id, prefix: prefix, hasGaps: hasGaps)
        }
        XCTAssertTrue(source.replaceData(Array(0..<1000), id: \.self, identityRoot: identity, rowContent: factory))
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 80,
                maximumMountedRecords: 16, maximumMountedLeaves: 32, maximumProtectedRecords: 2))
        let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
        list.retainedViewIdentity = identity
        list.retainedLazyListAdapter = adapter
        list.retainedSubtreeBuildLease = FinalPrefetchLease(probe: probe)
        self.source = source
        self.adapter = adapter
        self.list = list
        self.probe = probe
    }

    var rowIDs: [Int] {
        list.children.filter { $0.retainedLazyListGap == nil }.compactMap(\.dynamicContentIndex)
    }

    func weakRow(_ id: Int) -> FinalPrefetchWeakRow? { probe.rows.last { $0.id == id } }
}

@MainActor
private final class FinalPrefetchHookState {
    weak var request: RetainedLazyListUIARequest?
    var interventions = 0
    var offset: Double?
    var factoriesAtHook: Int?
    var probeMountedAtFinal: Bool?
}

@MainActor
private final class FinalPrefetchWeakRow {
    let id: Int
    weak var node: ViewNode?
    init(id: Int, node: ViewNode) {
        self.id = id
        self.node = node
    }
}

private struct FinalPrefetchFactoryCall {
    let id: Int
    let afterOwnedScroll: Bool
}

private struct FinalPrefetchBuildEvent {
    enum Kind: Equatable { case canBuild, begin, canAdopt, commit, abandon, finish }
    let kind: Kind
    let afterOwnedScroll: Bool
}

@MainActor
private final class FinalPrefetchProbe {
    weak var runtime: RetainedViewRuntime?
    var calls: [FinalPrefetchFactoryCall] = []
    var rows: [FinalPrefetchWeakRow] = []
    var events: [FinalPrefetchBuildEvent] = []
    var releases: [FinalPrefetchFactoryCall] = []
    var activations: [Int] = []
    var onCanBuild: (@MainActor @Sendable () -> Void)?
    var onCanAdopt: (@MainActor @Sendable () -> Void)?

    var afterOwnedScroll: Bool {
        runtime?.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll } == true
    }
    var factories: [Int] { calls.map(\.id) }
    var finalFactories: [FinalPrefetchFactoryCall] { calls.filter(\.afterOwnedScroll) }

    func finalEvents(of kind: FinalPrefetchBuildEvent.Kind) -> [FinalPrefetchBuildEvent] {
        events.filter { $0.afterOwnedScroll && $0.kind == kind }
    }

    func record(_ kind: FinalPrefetchBuildEvent.Kind) {
        events.append(.init(kind: kind, afterOwnedScroll: afterOwnedScroll))
    }

    func makeRows(_ id: Int, prefix: RetainedViewIdentity, hasGaps: Bool) -> [ViewNode] {
        calls.append(.init(id: id, afterOwnedScroll: afterOwnedScroll))
        let row = ViewNode(preferredSize: Size(width: 120, height: 20))
        row.retainedViewIdentity = prefix.appending(.slot(hasGaps ? 1 : 0)).appending(.role(.row))
        row.dynamicContentIndex = id
        row.accessibilityIdentifier = "uia.final.prefetch.\(id)"
        let payload = FinalPrefetchPayload(id: id, probe: self)
        row.onActivate = { [payload] in payload.activate() }
        rows.append(FinalPrefetchWeakRow(id: id, node: row))
        if !hasGaps { return [row] }
        let gap = ViewNode(preferredSize: Size(width: 120, height: 0), isHitTestVisible: false)
        gap.retainedViewIdentity = prefix.appending(.slot(0))
        gap.retainedLazyListGap = RetainedLazyListGap(
            spacing: 0, separatorThickness: 0, nextRowIsSelected: false, nextRowIsGrouped: false)
        return [gap, row]
    }

    func assertClosedEpochs(file: StaticString = #filePath, line: UInt = #line) {
        let begins = events.filter { $0.kind == .begin }.count
        XCTAssertEqual(
            begins, events.filter { $0.kind == .commit || $0.kind == .abandon }.count, file: file, line: line)
        XCTAssertEqual(begins, events.filter { $0.kind == .finish }.count, file: file, line: line)
        XCTAssertFalse(runtime?.hasActiveRetainedBuild ?? true, file: file, line: line)
    }
}

@MainActor
private final class FinalPrefetchPayload {
    let id: Int
    let probe: FinalPrefetchProbe
    init(id: Int, probe: FinalPrefetchProbe) {
        self.id = id
        self.probe = probe
    }
    func activate() { probe.activations.append(id) }
    isolated deinit { probe.releases.append(.init(id: id, afterOwnedScroll: probe.afterOwnedScroll)) }
}

@MainActor
private final class FinalPrefetchLease: RetainedSubtreeBuildLease {
    let probe: FinalPrefetchProbe
    init(probe: FinalPrefetchProbe) { self.probe = probe }
    var canBuild: Bool {
        probe.record(.canBuild)
        probe.onCanBuild?()
        return true
    }
    func beginBuild() -> (any RetainedBuildEpoch)? {
        probe.record(.begin)
        return FinalPrefetchEpoch(probe: probe)
    }
}

@MainActor
private final class FinalPrefetchEpoch: RetainedBuildEpoch {
    let probe: FinalPrefetchProbe
    private var prepared = false
    private var wasSuperseded = false
    init(probe: FinalPrefetchProbe) { self.probe = probe }
    var canAdopt: Bool {
        probe.record(.canAdopt)
        probe.onCanAdopt?()
        return !prepared && !wasSuperseded
    }
    func supersede() { if !prepared { wasSuperseded = true } }
    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        prepared = true
        return true
    }
    func commit() { probe.record(.commit) }
    func abandon() { probe.record(.abandon) }
    func finishAfterCallbacks() { probe.record(.finish) }
}

@MainActor
private final class FinalPrefetchPublicProbe {
    weak var runtime: RetainedViewRuntime?
    var calls: [FinalPrefetchFactoryCall] = []
    var activations: [Int] = []
    func makeRows(_ id: Int) -> [AnyView] {
        calls.append(
            .init(
                id: id,
                afterOwnedScroll: runtime?.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll } == true))
        return [AnyView(Button("Row \(id)") { [weak self] in self?.activations.append(id) }.frame(height: 24))]
    }
}

/// Native List reveal uses the same small raw lanes as the UIA controls above,
/// without creating a UIA request or supplying a private planning flag.
@MainActor
final class ListRevealPrefetchScopeTests: XCTestCase {
    func testSameScrollOmitsOptionalSiblingRowsButRealizesItsRequiredViewport() async throws {
        let fixture = try ListRevealPrefetchScopeFixture(hasIndependentScroll: false)
        defer { fixture.close() }
        let (receipt, target) = try fixture.prepareNavigation()
        defer { receipt.cancelPreparedNavigation() }
        fixture.arm()

        XCTAssertTrue(fixture.runtime.withLazyListResolutionBudget { receipt.finishNavigation() })

        try fixture.assertCompleted(target: target)
        let required = Set(18...20)
        XCTAssertEqual(Set(fixture.finalCalls(in: fixture.sibling, from: fixture.siblingFinalStart)), required)
        XCTAssertEqual(Set(fixture.sibling.rowIDs), required)
        XCTAssertTrue(required.isSubset(of: Set(fixture.primary.rowIDs)))
        XCTAssertTrue(Set(fixture.primary.rowIDs).isSubset(of: required.union([0])))
        XCTAssertTrue(
            Set(fixture.finalCalls(in: fixture.primary, from: fixture.primaryFinalStart)).isSubset(of: required))
        fixture.assertOriginalBudget()

        // An actual later viewport change needs row21. Optional rows should
        // resume on this ordinary build, after the reveal query has unwound.
        let primaryCalls = fixture.primary.probe.calls.count
        let siblingCalls = fixture.sibling.probe.calls.count
        fixture.scroll.onLayout = nil
        fixture.runtime.recordsLazyListUIAPhasesForTesting = true
        fixture.scroll.scrollOffset += 20
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.runtime.root))
        XCTAssertTrue(fixture.primary.probe.calls.dropFirst(primaryCalls).contains { $0.id > 21 })
        XCTAssertTrue(fixture.sibling.probe.calls.dropFirst(siblingCalls).contains { $0.id > 21 })
        XCTAssertTrue(fixture.primary.rowIDs.contains(21))
        XCTAssertTrue(fixture.sibling.rowIDs.contains(21))
        XCTAssertTrue(fixture.primary.rowIDs.contains { $0 > 21 })
        XCTAssertTrue(fixture.sibling.rowIDs.contains { $0 > 21 })
        fixture.assertOriginalBudget()
    }

    func testIndependentScrollKeepsOrdinaryPrefetchDuringTheOriginalRevealQuery() async throws {
        let fixture = try ListRevealPrefetchScopeFixture(hasIndependentScroll: true)
        defer { fixture.close() }
        let independent = try XCTUnwrap(fixture.independent)
        let independentScroll = try XCTUnwrap(fixture.independentScroll)
        let (receipt, target) = try fixture.prepareNavigation()
        defer { receipt.cancelPreparedNavigation() }
        fixture.arm()
        let focusRevision = fixture.runtime.presentationFocusRevision

        // The third adapter needs a separate provider round. Its accepted
        // rows still need measurements when the original four rounds end.
        XCTAssertFalse(fixture.runtime.withLazyListResolutionBudget { receipt.finishNavigation() })

        XCTAssertTrue(receipt.permitsContinuation)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertFalse(target.isFocused)
        XCTAssertEqual(fixture.runtime.presentationFocusRevision, focusRevision)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .budgetExhausted)
        switch fixture.runtime.layoutSettlementStatus {
        case .unsettled: break
        default: XCTFail("The accepted reveal must wait for the remaining adapter measurements")
        }
        XCTAssertNotNil(fixture.primaryFinalStart)
        XCTAssertNotNil(fixture.siblingFinalStart)
        XCTAssertEqual(fixture.scroll.scrollOffset, 360)
        XCTAssertFalse(target.isLayoutDeferredByVirtualization)
        XCTAssertTrue(target.parent === fixture.primary.list)
        XCTAssertTrue(fixture.runtime.lazyListUIAPhasesForTesting.allSatisfy { $0.kind != .ownedScroll })
        XCTAssertTrue(fixture.primary.probe.activations.isEmpty)
        XCTAssertTrue(fixture.sibling.probe.activations.isEmpty)
        XCTAssertEqual(independentScroll.scrollOffset, 360)
        let required = Set(18...20)
        let calls = fixture.finalCalls(in: independent, from: fixture.independentFinalStart)
        XCTAssertTrue(required.isSubset(of: Set(calls)))
        XCTAssertTrue(calls.contains { $0 > 20 }, "A separate scroll must retain optional prefetch")
        XCTAssertTrue(required.isSubset(of: Set(independent.rowIDs)))
        XCTAssertTrue(independent.rowIDs.contains { $0 > 20 })
        XCTAssertEqual(Set(fixture.sibling.rowIDs), required)
        XCTAssertTrue(
            Set(fixture.finalCalls(in: fixture.sibling, from: fixture.siblingFinalStart)).isSubset(of: required))
        fixture.assertOriginalBudget()

        // Only ordinary frames may finish this already-accepted reveal. Do
        // not call finishNavigation again or lend it another action's receipt.
        for _ in 0..<4 where fixture.runtime.focusedNode !== target {
            fixture.runtime.recordsLazyListUIAPhasesForTesting = true
            _ = fixture.runtime.renderFrame()
            fixture.assertOriginalBudget()
            XCTAssertTrue(target.parent === fixture.primary.list)
            XCTAssertEqual(fixture.scroll.scrollOffset, 360)
            XCTAssertEqual(independentScroll.scrollOffset, 360)
        }

        try fixture.assertCompleted(target: target)
        XCTAssertEqual(independentScroll.scrollOffset, 360)
        XCTAssertGreaterThan(target.resolvedFrame.maxY, fixture.scroll.resolvedScrollOffset)
        XCTAssertLessThan(
            target.resolvedFrame.minY, fixture.scroll.resolvedScrollOffset + fixture.scroll.resolvedFrame.height)
        XCTAssertEqual(fixture.runtime.presentationFocusRevision, focusRevision + 1)
    }
}

@MainActor
private final class ListRevealPrefetchScopeFixture {
    let primary: FinalPrefetchLane
    let sibling: FinalPrefetchLane
    let independent: FinalPrefetchLane?
    let scroll: ViewNode
    let independentScroll: ViewNode?
    let runtime: RetainedViewRuntime
    let scope: RetainedListNavigationOwner
    private(set) var primaryFinalStart: Int?
    private(set) var siblingFinalStart: Int?
    private(set) var independentFinalStart: Int?

    init(hasIndependentScroll: Bool) throws {
        let primary = try FinalPrefetchLane(slot: 10, hasGaps: false)
        let sibling = try FinalPrefetchLane(slot: 11, hasGaps: false)
        let independent: FinalPrefetchLane? =
            try hasIndependentScroll ? FinalPrefetchLane(slot: 12, hasGaps: false) : nil
        let columns = ViewNode(
            layoutMode: .stack(.horizontal(spacing: 0, alignment: .leading, distribution: .fillEqually)),
            children: [primary.list, sibling.list])
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 240, height: 60), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical,
            children: [columns])
        let independentScroll = independent.map { lane in
            ViewNode(
                frame: Rect(x: 240, y: 0, width: 120, height: 60), clipsToBounds: true,
                layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical,
                children: [lane.list])
        }
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: hasIndependentScroll ? 360 : 240, height: 60),
            children: [scroll] + (independentScroll.map { [$0] } ?? []))
        let runtime = RetainedViewRuntime(root: root)
        let scope = RetainedListNavigationOwner(runtime: runtime)
        scope.install(on: scroll)
        runtime.clock = { 0 }
        self.primary = primary
        self.sibling = sibling
        self.independent = independent
        self.scroll = scroll
        self.independentScroll = independentScroll
        self.runtime = runtime
        self.scope = scope
        for lane in [primary, sibling] + (independent.map { [$0] } ?? []) { lane.probe.runtime = runtime }
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root))
        XCTAssertEqual(primary.rowIDs, Array(0...6))
        XCTAssertEqual(sibling.rowIDs, Array(0...6))
        if let independent { XCTAssertEqual(independent.rowIDs, Array(0...6)) }
    }

    func prepareNavigation() throws -> (RetainedListNavigationReceipt, ViewNode) {
        XCTAssertFalse(primary.rowIDs.contains(20))
        let item = try XCTUnwrap(runtime.lazyListTarget(in: primary.list, key: .init(20)))
        defer { runtime.releaseLazyListTarget(item) }
        let target = try XCTUnwrap(runtime.realizeLazyListTarget(item))
        XCTAssertEqual(target.dynamicContentIndex, 20)
        XCTAssertEqual(scroll.scrollOffset, 0)
        XCTAssertGreaterThan(target.resolvedFrame.minY, scroll.resolvedFrame.height)
        let source = try XCTUnwrap(primary.weakRow(0)?.node)
        for row in [source, target] {
            row.isFocusable = true
            row.isFocusEnabled = true
            row.accessibilityTraits = .isSelectable
            row.interceptsVerticalArrowKeys = true
            _ = scope.makeRowOwner(on: row)
        }
        let receipt = try XCTUnwrap(scope.prepareAction(from: try XCTUnwrap(source.listNavigationOwner)))
        XCTAssertTrue(receipt.prepareTarget(try XCTUnwrap(target.listNavigationOwner), requiresRevealBeforeFocus: true))
        return (receipt, target)
    }

    func arm() {
        runtime.recordsLazyListUIAPhasesForTesting = true
        scroll.onLayout = { [weak self] _ in
            guard let self, self.scroll.scrollOffset > 0, self.primaryFinalStart == nil else { return }
            self.primaryFinalStart = self.primary.probe.calls.count
            self.siblingFinalStart = self.sibling.probe.calls.count
            self.independentFinalStart = self.independent?.probe.calls.count
            // Expose a required viewport in another physical scroll during
            // this same query. The target's scroll intent is unchanged.
            self.independentScroll?.scrollOffset = self.scroll.scrollOffset
        }
    }

    func finalCalls(in lane: FinalPrefetchLane, from start: Int?) -> [Int] {
        guard let start else {
            XCTFail("The original reveal must reach its post-offset layout")
            return []
        }
        return lane.probe.calls.dropFirst(start).map(\.id)
    }

    func assertCompleted(target: ViewNode) throws {
        XCTAssertNotNil(primaryFinalStart)
        XCTAssertNotNil(siblingFinalStart)
        XCTAssertEqual(scroll.scrollOffset, 360)
        XCTAssertTrue(runtime.focusedNode === target)
        XCTAssertTrue(target.isFocused)
        XCTAssertFalse(target.isLayoutDeferredByVirtualization)
        XCTAssertTrue(target.parent === primary.list)
        XCTAssertTrue(runtime.lazyListUIAPhasesForTesting.allSatisfy { $0.kind != .ownedScroll })
        XCTAssertTrue(primary.probe.activations.isEmpty)
        XCTAssertTrue(sibling.probe.activations.isEmpty)
    }

    func assertOriginalBudget(file: StaticString = #filePath, line: UInt = #line) {
        let trace = runtime.lazyListUIAPhasesForTesting
        XCTAssertFalse(trace.isEmpty, file: file, line: line)
        XCTAssertLessThan(trace.count, 512, file: file, line: line)
        XCTAssertEqual(trace.first?.remainingElements, 128, file: file, line: line)
        XCTAssertEqual(trace.first?.remainingRounds, 4, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedElements, 128, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedRounds, 4, file: file, line: line)
        XCTAssertEqual(
            trace.filter { $0.kind == .roundDebit }.count, runtime.lastLazyListConsumedRounds, file: file, line: line)
        for (first, second) in zip(trace, trace.dropFirst()) {
            XCTAssertGreaterThanOrEqual(first.remainingElements, second.remainingElements, file: file, line: line)
            XCTAssertGreaterThanOrEqual(first.remainingRounds, second.remainingRounds, file: file, line: line)
        }
        XCTAssertEqual(runtime.lazyListResolutionBudgetConfiguration.elementLimit, 128, file: file, line: line)
        XCTAssertEqual(runtime.lazyListResolutionBudgetConfiguration.roundLimit, 4, file: file, line: line)
    }

    func close() {
        scroll.onLayout = nil
        runtime.stopRenderLifecycleCallbacks()
        for lane in [primary, sibling] + (independent.map { [$0] } ?? []) {
            lane.probe.onCanBuild = nil
            lane.probe.onCanAdopt = nil
            lane.source.close()
        }
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}
