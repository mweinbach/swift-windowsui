import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Isolates ordinary preparation of the selected distant record. The original
/// keyboard tests still require immediate Down-to-900 and Up-to-899 navigation.
@MainActor
final class ManagedListTargetReadinessTests: XCTestCase {
    private static let viewport = IntSize(width: 260, height: 200)

    private func makeManagedRuntime<V: View>(
        _ view: V, size: IntSize = ManagedListTargetReadinessTests.viewport
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

    func testSelectedDistantManagedRecordBecomesReadyWithinOriginalBudget() async throws {
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
        selection = 899

        // Use the same attached source and logical table as the original handler.
        // This test prepares 899 only; it neither invokes nor replaces that handler.
        defer { withExtendedLifetime(sourceKeyDown) {} }
        let runtime = result.runtime
        let content = try result.list()
        let scroll = try result.scrollContainer()
        let adapter = try XCTUnwrap(content.retainedLazyListAdapter)
        let sourceOwner = try XCTUnwrap(source.listNavigationOwner)
        let scope = try XCTUnwrap(scroll.listNavigationOwner)
        let receipt = try XCTUnwrap(scope.prepareAction(from: sourceOwner))
        defer { receipt.cancelPreparedNavigation() }
        let table = try XCTUnwrap(DeferredListScrollSource.attached(to: content))
        let logicalRow = try XCTUnwrap(table.row(at: 899))
        let item = try XCTUnwrap(runtime.lazyListTarget(in: content, key: logicalRow.providerKey))
        defer { runtime.releaseLazyListTarget(item) }
        let originalFocus = runtime.focusedNode
        let originalOffset = scroll.scrollOffset
        XCTAssertEqual(adapter.logicalRecordCount, 1_000)
        XCTAssertNil(item.knownLeafCount)
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertTrue(receipt.permitsBindingWrite)

        let resolution = runtime.withLazyListResolutionBudget {
            runtime.resolveLazyListTarget(item)
        }

        assertDefaultBudgetBounds(runtime)
        XCTAssertEqual(runtime.lastLazyListWorkCompletion, .complete)
        XCTAssertTrue(runtime.isLazyListAccessibilityItemCurrent(item))
        XCTAssertTrue(receipt.permitsBindingWrite)
        XCTAssertTrue(source.listNavigationOwner === sourceOwner)
        XCTAssertTrue(source.parent === content)
        XCTAssertTrue(source.retainedLazyListRuntime === runtime)
        XCTAssertEqual(selection, 899)
        XCTAssertEqual(scroll.scrollOffset, originalOffset)
        XCTAssertTrue(runtime.focusedNode === originalFocus)
        XCTAssertNil(result.find("virtual-row-900"))
        guard case .ready(let roots) = resolution else {
            return XCTFail("Selected record 899 must be ready immediately; \(budgetSummary(runtime))")
        }
        try assertReady899(roots, in: result, item: item)
    }

    func testRequiredRecordAndSinglePredecessorUseTheSameProviderPhase() async throws {
        let trace = ManagedListFactoryTrace()
        var selection: Int? = 0
        let binding = Binding<Int?>(get: { selection }, set: { selection = $0 })
        let result = makeManagedRuntime(
            List(0..<1_000, id: \.self, selection: binding) { index in
                let _ = trace.record(index)
                self.row(index)
            }
        )
        defer { result.close() }
        try settle(result)
        let source = try result.rowRoot("virtual-row-0")
        XCTAssertNotNil(source.onKeyDown)
        XCTAssertNil(result.find("virtual-row-899"))
        XCTAssertNil(result.find("virtual-row-898"))
        XCTAssertNil(result.find("virtual-row-900"))
        selection = 899

        let runtime = result.runtime
        let content = try result.list()
        let scroll = try result.scrollContainer()
        let adapter = try XCTUnwrap(content.retainedLazyListAdapter)
        let sourceOwner = try XCTUnwrap(source.listNavigationOwner)
        let scope = try XCTUnwrap(scroll.listNavigationOwner)
        let receipt = try XCTUnwrap(scope.prepareAction(from: sourceOwner))
        defer { receipt.cancelPreparedNavigation() }
        let table = try XCTUnwrap(DeferredListScrollSource.attached(to: content))
        let logicalRow = try XCTUnwrap(table.row(at: 899))
        let item = try XCTUnwrap(runtime.lazyListTarget(in: content, key: logicalRow.providerKey))
        defer { runtime.releaseLazyListTarget(item) }
        let originalFocus = runtime.focusedNode
        let originalOffset = scroll.scrollOffset
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertNil(item.knownLeafCount)
        XCTAssertTrue(receipt.permitsBindingWrite)

        // Recording starts after ordinary fixture construction. Reading the
        // existing phase marker does not create a query or provider authority.
        trace.runtime = runtime
        trace.isRecording = true
        runtime.recordsLazyListUIAPhasesForTesting = true
        let resolution = runtime.withLazyListResolutionBudget {
            runtime.resolveLazyListTarget(item)
        }
        runtime.recordsLazyListUIAPhasesForTesting = false
        trace.isRecording = false
        let phases = runtime.lazyListUIAPhasesForTesting

        assertDefaultBudgetBounds(runtime)
        assertOrdinaryPhases(phases)
        XCTAssertFalse(trace.overflowed)
        XCTAssertEqual(trace.entries.map(\.ordinal), [899, 898])
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 2)
        XCTAssertEqual(runtime.lastLazyListWorkCompletion, .complete)
        XCTAssertTrue(runtime.isLazyListAccessibilityItemCurrent(item))
        XCTAssertTrue(receipt.permitsBindingWrite)
        XCTAssertTrue(source.listNavigationOwner === sourceOwner)
        XCTAssertTrue(source.parent === content)
        XCTAssertEqual(selection, 899)
        XCTAssertEqual(scroll.scrollOffset, originalOffset)
        XCTAssertTrue(runtime.focusedNode === originalFocus)
        XCTAssertNil(result.find("virtual-row-900"))
        guard trace.entries.count == 2 else {
            return XCTFail("Only required 899 and its one predecessor may invoke factories")
        }
        let required = trace.entries[0]
        let predecessor = trace.entries[1]
        XCTAssertEqual(required.phase?.kind, .providerPhase)
        XCTAssertEqual(predecessor.phase?.kind, .providerPhase)
        XCTAssertGreaterThanOrEqual(required.phaseIndex, 0)
        XCTAssertEqual(required.phaseIndex, predecessor.phaseIndex)
        XCTAssertEqual(required.phase?.layoutPassID, predecessor.phase?.layoutPassID)
        XCTAssertEqual(required.phase?.resolutionSequence, predecessor.phase?.resolutionSequence)
        guard case .ready(let roots) = resolution else {
            return XCTFail("The same-provider required/probe work must settle; \(budgetSummary(runtime))")
        }
        try assertReady899(roots, in: result, item: item)
    }

    func testCancellingOriginalRealizationInRequiredFactoryPreventsProbeAndAdoption() async throws {
        let trace = ManagedListFactoryTrace()
        var selection: Int? = 0
        let binding = Binding<Int?>(get: { selection }, set: { selection = $0 })
        let result = makeManagedRuntime(
            List(0..<1_000, id: \.self, selection: binding) { index in
                let _ = trace.record(index)
                self.row(index)
            }
        )
        defer {
            trace.onRequiredFactory = nil
            result.close()
        }
        try settle(result)
        let source = try result.rowRoot("virtual-row-0")
        XCTAssertNotNil(source.onKeyDown)
        XCTAssertNil(result.find("virtual-row-899"))
        XCTAssertNil(result.find("virtual-row-898"))
        selection = 899

        let runtime = result.runtime
        let content = try result.list()
        let scroll = try result.scrollContainer()
        let adapter = try XCTUnwrap(content.retainedLazyListAdapter)
        let sourceOwner = try XCTUnwrap(source.listNavigationOwner)
        let scope = try XCTUnwrap(scroll.listNavigationOwner)
        let receipt = try XCTUnwrap(scope.prepareAction(from: sourceOwner))
        defer { receipt.cancelPreparedNavigation() }
        let table = try XCTUnwrap(DeferredListScrollSource.attached(to: content))
        let logicalRow = try XCTUnwrap(table.row(at: 899))
        let item = try XCTUnwrap(runtime.lazyListTarget(in: content, key: logicalRow.providerKey))
        defer { runtime.releaseLazyListTarget(item) }
        let originalFocus = runtime.focusedNode
        let originalOffset = scroll.scrollOffset
        let originalResolutions = runtime.lazyListResolveCount
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertNil(item.knownLeafCount)
        XCTAssertTrue(receipt.permitsBindingWrite)

        trace.runtime = runtime
        trace.onRequiredFactory = { [weak runtime] in
            // Cancel this exact original demand, without replacing its logical
            // item or acquiring any new action/realization inside the factory.
            runtime?.releaseLazyListTarget(item)
        }
        trace.isRecording = true
        runtime.recordsLazyListUIAPhasesForTesting = true
        let resolution = runtime.withLazyListResolutionBudget {
            runtime.resolveLazyListTarget(item)
        }
        runtime.recordsLazyListUIAPhasesForTesting = false
        trace.isRecording = false
        let phases = runtime.lazyListUIAPhasesForTesting

        assertDefaultBudgetBounds(runtime)
        assertOrdinaryPhases(phases)
        XCTAssertFalse(trace.overflowed)
        XCTAssertEqual(trace.entries.map(\.ordinal), [899])
        XCTAssertEqual(trace.requiredCallbackInvocations, 1)
        XCTAssertNil(trace.onRequiredFactory)
        XCTAssertEqual(trace.entries.first?.phase?.kind, .providerPhase)
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 1)
        // The counter excludes a completed accepted resolution. The native
        // membership checks below separately reject a surviving stale row.
        XCTAssertEqual(runtime.lazyListResolveCount, originalResolutions)
        XCTAssertNil(adapter.mountedNodes(for: item.token))
        XCTAssertNil(adapter.knownLeafCount(for: item.token))
        XCTAssertNil(result.find("virtual-row-899"))
        XCTAssertNil(result.find("virtual-row-898"))
        XCTAssertNil(result.find("virtual-row-900"))
        XCTAssertTrue(runtime.isLazyListAccessibilityItemCurrent(item))
        XCTAssertTrue(receipt.permitsBindingWrite)
        XCTAssertTrue(source.listNavigationOwner === sourceOwner)
        XCTAssertTrue(source.parent === content)
        XCTAssertTrue(source.retainedLazyListRuntime === runtime)
        XCTAssertEqual(selection, 899)
        XCTAssertEqual(scroll.scrollOffset, originalOffset)
        XCTAssertTrue(runtime.focusedNode === originalFocus)
        // Releasing a realization does not expire the source's logical token.
        guard case .pending = resolution else {
            return XCTFail("A cancelled realization must not become ready; \(budgetSummary(runtime))")
        }
    }

    private func assertReady899(
        _ roots: [ViewNode], in host: MountedLazyListTestHost, item: RetainedLazyListAccessibilityItem,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let target = try host.rowRoot("virtual-row-899", file: file, line: line)
        let content = try host.list(file: file, line: line)
        let adapter = try XCTUnwrap(content.retainedLazyListAdapter, file: file, line: line)
        let eligible = roots.filter { node in
            !node.isHidden && !node.isSeparatorRule && node.isFocusEnabled && node.listNavigationOwner != nil
                && DeferredListRowNavigation.attached(to: node)?.ordinal == 899
        }
        XCTAssertEqual(eligible.count, 1, file: file, line: line)
        XCTAssertTrue(eligible.first === target, file: file, line: line)
        XCTAssertEqual(DeferredListRowNavigation.attached(to: target)?.leaf, 0, file: file, line: line)
        XCTAssertNotNil(target.onKeyDown, file: file, line: line)
        XCTAssertFalse(target.isLayoutDeferredByVirtualization, file: file, line: line)
        XCTAssertTrue(target.parent === content, file: file, line: line)
        XCTAssertTrue(target.retainedLazyListRuntime === host.runtime, file: file, line: line)
        XCTAssertTrue(
            adapter.mountedNodes(for: item.token)?.contains(where: { $0 === target }) == true,
            file: file, line: line)
        XCTAssertFalse(adapter.hasUnresolvedWork, file: file, line: line)
        guard case .settled = host.runtime.layoutSettlementStatus else {
            return XCTFail("Ready ordinary roots require actual settled layout", file: file, line: line)
        }
    }

    private func assertDefaultBudgetBounds(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(runtime.lastLazyListConsumedRounds, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedRounds, 4, file: file, line: line)
        XCTAssertGreaterThanOrEqual(runtime.lastLazyListConsumedElements, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedElements, 128, file: file, line: line)
    }

    private func assertOrdinaryPhases(
        _ phases: [RetainedViewRuntime.LazyListUIAPhaseTrace],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(phases.isEmpty, file: file, line: line)
        XCTAssertLessThan(phases.count, 512, file: file, line: line)
        XCTAssertEqual(phases.first?.remainingRounds, 4, file: file, line: line)
        XCTAssertEqual(phases.first?.remainingElements, 128, file: file, line: line)
        XCTAssertTrue(
            phases.allSatisfy { $0.mutationRevision == 0 && $0.activePhysicalActivityIDs == nil },
            file: file, line: line)
    }

    private func budgetSummary(_ runtime: RetainedViewRuntime) -> String {
        "rounds=\(runtime.lastLazyListConsumedRounds), elements=\(runtime.lastLazyListConsumedElements), "
            + "completion=\(runtime.lastLazyListWorkCompletion)"
    }
}

/// Only the two instrumented fixtures use this recorder. The original fixture
/// above has no additional row-factory callback or phase-recording flag.
@MainActor
private final class ManagedListFactoryTrace {
    struct Entry {
        let ordinal: Int
        let phaseIndex: Int
        let phase: RetainedViewRuntime.LazyListUIAPhaseTrace?
    }

    weak var runtime: RetainedViewRuntime?
    var isRecording = false
    var onRequiredFactory: (() -> Void)?
    private(set) var entries: [Entry] = []
    private(set) var overflowed = false
    private(set) var requiredCallbackInvocations = 0

    func record(_ ordinal: Int) {
        guard isRecording else { return }
        if entries.count < 128 {
            let count = runtime?.lazyListUIAPhasesForTesting.count ?? 0
            entries.append(
                Entry(
                    ordinal: ordinal, phaseIndex: count - 1,
                    phase: runtime?.lazyListUIAPhasesForTesting.last))
        } else {
            overflowed = true
        }
        if ordinal == 899, let callback = onRequiredFactory {
            onRequiredFactory = nil
            requiredCallbackInvocations += 1
            callback()
        }
    }
}
