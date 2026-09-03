import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Native managed leaves only: the primitive supplies an explicit structural
/// role, without claiming that a facade ViewThatFits policy chose the leaf.
@MainActor
final class LazyListSelectedContentUIATargetTests: XCTestCase {
    func testNativeTargetUsesSelectedGeometryWithoutReplacingItsPhysicalIdentity() async throws {
        let fixture = try SelectedContentUIAFixture()
        defer { fixture.host.close() }
        let runtime = fixture.host.runtime
        let token = try fixture.token(300)
        let witness = try XCTUnwrap(runtime.lazyListTarget(in: fixture.list, token: token))
        XCTAssertFalse(fixture.probe.factories.contains(300))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true

        try runtime.withLazyListResolutionBudget {
            let request = try XCTUnwrap(
                runtime.prepareLazyListUIARequest(token: token, in: witness, during: mutation))
            defer { runtime.finishLazyListUIARequest(request) }
            XCTAssertEqual(request.item.token, token)

            let roots = try XCTUnwrap(runtime.resolveLazyListUIARequest(request))
            let capture = try XCTUnwrap(fixture.probe.firstRows[300])
            let physical = try XCTUnwrap(capture.physical)
            let inner = try XCTUnwrap(capture.inner)
            let selected = try XCTUnwrap(capture.selected)
            XCTAssertEqual(try XCTUnwrap(capture.token), token)
            XCTAssertEqual(roots.count, 1)
            XCTAssertTrue(roots.first === physical)
            XCTAssertTrue(fixture.adapter.mountedNodes(for: token)?.first === physical)
            XCTAssertEqual(fixture.adapter.mountedToken(containing: physical), token)
            XCTAssertTrue(physical.parent === fixture.list)
            XCTAssertTrue(physical.children.first === inner)
            XCTAssertTrue(inner.children.first === selected)
            XCTAssertTrue(selected.parent === inner)
            XCTAssertTrue(physical.retainedLazyListRuntime === runtime)
            XCTAssertTrue(selected.retainedLazyListRuntime === runtime)
            XCTAssertEqual(physical.selectedContentRole, .viewThatFits)
            XCTAssertEqual(inner.selectedContentRole, .viewThatFits)
            XCTAssertEqual(physical.resolvedFrame, .zero)
            XCTAssertEqual(inner.resolvedFrame, .zero)
            XCTAssertEqual(selected.resolvedFrame, Rect(x: 0, y: 6_000, width: 120, height: 20))

            let bounds = try XCTUnwrap(fixture.adapter.logicalBounds(for: token))
            XCTAssertEqual(fixture.adapter.knownLeafCount(for: token), 1)
            XCTAssertEqual(bounds.origin, 6_000)
            XCTAssertEqual(bounds.extent, 20)
            XCTAssertEqual(fixture.adapter.contentExtent, 20_000)
            XCTAssertEqual(fixture.list.resolvedFrame.origin.y, 0)
            XCTAssertEqual(fixture.scroll.resolvedFrame.size, Size(width: 120, height: 40))
            // The selected origin contributes once through both zero-frame
            // boundaries: 6_000 + 20 - the explicit 40-point viewport.
            XCTAssertEqual(fixture.scroll.scrollOffset, 5_980)
            XCTAssertEqual(fixture.probe.factories.filter { $0 == 300 }.count, 1)

            let dispatch = runtime.currentPrepaintState.dispatchNodes
            XCTAssertTrue(dispatch.contains { $0.node === selected })
            XCTAssertFalse(dispatch.contains { $0.node === physical || $0.node === inner })
            XCTAssertTrue(runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint)
            guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
                return XCTFail("The original native request must supply its own completed settlement")
            }
            XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
            XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
            XCTAssertFalse(runtime.hasActiveRetainedBuild)

            let trace = runtime.lazyListUIAPhasesForTesting
            let completed = try XCTUnwrap(trace.last)
            XCTAssertEqual(trace.filter { $0.kind == .ownedScroll }.count, 1)
            XCTAssertEqual(trace.filter { $0.kind == .roundDebit }.count, completed.consumedRounds)
            XCTAssertTrue(trace.allSatisfy { $0.consumedRounds + $0.remainingRounds == 4 })
            XCTAssertTrue(trace.allSatisfy { (0...128).contains($0.remainingElements) })
        }
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedRounds, 4)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedElements, 128)
    }

    func testSelectedABARejectsTheSavedNativePhaseWithoutAnotherQuery() async throws {
        let fixture = try SelectedContentUIAFixture()
        defer { fixture.host.close() }
        let runtime = fixture.host.runtime
        let token = try fixture.token(300)
        let warmToken = try fixture.token(0)
        let witness = try XCTUnwrap(runtime.lazyListTarget(in: fixture.list, token: token))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true
        var originalConsumedRounds = 0
        var originalConsumedElements = 0

        try runtime.withLazyListResolutionBudget {
            let request = try XCTUnwrap(
                runtime.prepareLazyListUIARequest(token: token, in: witness, during: mutation))
            defer { runtime.finishLazyListUIARequest(request) }
            let preparedTrace = runtime.lazyListUIAPhasesForTesting
            let saved = try XCTUnwrap(preparedTrace.last { $0.kind == .savedProviderPhase })
            let prepared = try XCTUnwrap(preparedTrace.last)
            XCTAssertEqual(preparedTrace.filter { $0.kind == .savedProviderPhase }.count, 1)
            XCTAssertFalse(
                preparedTrace.contains { $0.kind == .resumedProviderPhase || $0.kind == .revokedProviderPhase })
            XCTAssertFalse(
                preparedTrace.contains {
                    $0.consumedRounds == saved.consumedRounds
                        && ($0.kind == .readerPhase || $0.kind == .providerPhase)
                })
            XCTAssertGreaterThan(saved.remainingRounds, 0)
            XCTAssertEqual(saved.consumedRounds + saved.remainingRounds, 4)
            XCTAssertFalse(fixture.probe.factories.contains(300))

            let capture = try XCTUnwrap(fixture.probe.firstRows[0])
            let physical = try XCTUnwrap(capture.physical)
            let inner = try XCTUnwrap(capture.inner)
            let selected = try XCTUnwrap(capture.selected)
            XCTAssertEqual(try XCTUnwrap(capture.token), warmToken)
            XCTAssertTrue(fixture.adapter.mountedNodes(for: warmToken)?.first === physical)
            let originalPath = try XCTUnwrap(physical.captureSelectedContentPath(in: runtime))
            XCTAssertTrue(originalPath.isCurrent)
            XCTAssertTrue(originalPath.isInstalled(in: runtime))
            XCTAssertTrue(originalPath.physicalRoot === physical)
            XCTAssertTrue(originalPath.selectedNode === selected)
            XCTAssertEqual(physical.resolvedFrame, .zero)
            XCTAssertEqual(inner.resolvedFrame, .zero)
            XCTAssertEqual(selected.resolvedFrame, Rect(x: 0, y: 0, width: 120, height: 20))
            let frames = [physical.resolvedFrame, inner.resolvedFrame, selected.resolvedFrame]
            let pass = runtime.layoutPassID
            let prepaint = ObjectIdentifier(runtime.currentPrepaintState.generation)
            let factories = fixture.probe.factories
            originalConsumedRounds = prepared.consumedRounds
            originalConsumedElements = 128 - prepared.remainingElements

            let replacement = ViewNode(preferredSize: Size(width: 120, height: 20))
            inner.setChildren([replacement])
            XCTAssertFalse(originalPath.isCurrent)
            inner.setChildren([selected])

            XCTAssertTrue(physical.parent === fixture.list)
            XCTAssertTrue(physical.children.first === inner)
            XCTAssertTrue(inner.children.first === selected)
            XCTAssertTrue(selected.parent === inner)
            XCTAssertTrue(fixture.adapter.mountedNodes(for: warmToken)?.first === physical)
            XCTAssertEqual([physical.resolvedFrame, inner.resolvedFrame, selected.resolvedFrame], frames)
            XCTAssertTrue(originalPath.physicalRoot === physical)
            XCTAssertTrue(originalPath.selectedNode === selected)
            XCTAssertFalse(originalPath.isCurrent, "Restored objects and scalars cannot renew the original selection")

            XCTAssertNil(runtime.resolveLazyListUIARequest(request))

            XCTAssertEqual(fixture.probe.factories, factories)
            XCTAssertFalse(fixture.probe.factories.contains(300))
            XCTAssertEqual(runtime.layoutPassID, pass)
            XCTAssertEqual(ObjectIdentifier(runtime.currentPrepaintState.generation), prepaint)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertFalse(runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertFalse(runtime.hasActiveRetainedBuild)
            XCTAssertFalse(originalPath.isCurrent)
            let rejectedTrace = runtime.lazyListUIAPhasesForTesting
            // Revocation may be recorded here or by the owed finish. It cannot
            // conceal another query, debit, saved phase, or authored phase.
            let operationTrace = rejectedTrace.filter { $0.kind != .revokedProviderPhase }
            XCTAssertEqual(operationTrace.map(\.kind), preparedTrace.map(\.kind))
            XCTAssertEqual(operationTrace.map(\.layoutPassID), preparedTrace.map(\.layoutPassID))
            XCTAssertEqual(operationTrace.map(\.resolutionSequence), preparedTrace.map(\.resolutionSequence))
            XCTAssertFalse(rejectedTrace.contains { $0.kind == .resumedProviderPhase || $0.kind == .ownedScroll })
            let rejected = try XCTUnwrap(rejectedTrace.last)
            XCTAssertEqual(rejected.consumedRounds, prepared.consumedRounds)
            XCTAssertEqual(rejected.remainingRounds, prepared.remainingRounds)
            XCTAssertEqual(rejected.remainingElements, prepared.remainingElements)
        }
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, originalConsumedRounds)
        XCTAssertEqual(runtime.lastLazyListConsumedElements, originalConsumedElements)
    }
}

@MainActor
private final class SelectedContentUIAFixture {
    let probe: SelectedContentUIAProbe
    let host: MountedLazyListTestHost
    let list: ViewNode
    let scroll: ViewNode
    let adapter: RetainedLazyListRuntimeAdapter

    init() throws {
        let probe = SelectedContentUIAProbe()
        self.probe = probe
        let host = MountedLazyListTestHost(size: Size(width: 120, height: 40)) {
            ManagedLazyListContent(
                Array(0..<1000), id: \.self, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
            ) { id in
                SelectedContentUIALeaf(id: id, probe: probe)
            }
        }
        self.host = host
        do {
            XCTAssertEqual(host.runtime.root.frame.size, Size(width: 120, height: 40))
            XCTAssertNotNil(host.layout())
            list = try host.list()
            scroll = try host.scrollContainer()
            adapter = try XCTUnwrap(list.retainedLazyListAdapter)
            XCTAssertEqual(host.runtime.root.resolvedFrame.size, Size(width: 120, height: 40))
            XCTAssertEqual(scroll.resolvedFrame.size, Size(width: 120, height: 40))
            XCTAssertEqual(list.resolvedFrame.origin.y, 0)
            XCTAssertEqual(list.resolvedFrame.width, 120)
            XCTAssertEqual(scroll.scrollOffset, 0)
            XCTAssertEqual(adapter.contentExtent, 20_000)
            XCTAssertNotNil(adapter.managedLogicalDescriptorBinding)
            XCTAssertTrue(adapter.managedLogicalDescriptorBinding?.isCurrent == true)
            XCTAssertFalse(adapter.hasUnresolvedWork)
            XCTAssertEqual(probe.factories, [0, 1])
            XCTAssertEqual(host.runtime.lastLazyListConsumedElements, 2)
            XCTAssertEqual(host.runtime.lastLazyListConsumedRounds, 2)
            XCTAssertTrue(host.runtime.hasCurrentAccessibilityPrepaint)
        } catch {
            host.close()
            throw error
        }
    }

    func token(_ id: Int) throws -> RetainedLazyListRowToken {
        try XCTUnwrap(adapter.token(for: RetainedViewIdentity.Key(id)))
    }
}

@MainActor
private final class SelectedContentUIARow {
    weak var physical: ViewNode?
    weak var inner: ViewNode?
    weak var selected: ViewNode?
    let token: RetainedLazyListRowToken?

    init(physical: ViewNode, inner: ViewNode, selected: ViewNode, token: RetainedLazyListRowToken?) {
        self.physical = physical
        self.inner = inner
        self.selected = selected
        self.token = token
    }
}

@MainActor
private final class SelectedContentUIAProbe {
    var factories: [Int] = []
    var firstRows: [Int: SelectedContentUIARow] = [:]

    func makeNode(_ id: Int, context: ViewBuildContext) -> ViewNode {
        factories.append(id)
        let selected = ViewNode(preferredSize: Size(width: 120, height: 20), backgroundColor: .blue)
        selected.accessibilityIdentifier = "uia.selected.leaf.\(id)"
        let inner = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)
        let physical = ViewNode.selectedContentBoundary(role: .viewThatFits, child: inner)
        if firstRows[id] == nil {
            firstRows[id] = SelectedContentUIARow(
                physical: physical, inner: inner, selected: selected,
                token: context.viewIdentity.lazyList?.native.rowRequest.token)
        }
        return physical
    }
}

@MainActor
private struct SelectedContentUIALeaf: View {
    typealias Body = Never
    let id: Int
    let probe: SelectedContentUIAProbe
    var body: Never { fatalError("Primitive") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in probe.makeNode(id, context: context) }
    }
}
