import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A public frame is an actual row root, but is not a pointer target. These
/// cases use the real public List and retained UIA request, not a visibility
/// predicate substitute. The explicit allowance isolates final visibility
/// from the separate default-four optional-prefetch measurement problem.
@MainActor
final class LazyListUIAFramedRowVisibilityTests: XCTestCase {
    func testPublicFramedButtonIsRevealedWithoutARowPointerInteraction() async throws {
        let fixture = try FramedUIAVisibilityFixture(scenario: .visible)
        defer { fixture.host.close() }
        let source = RuntimeUIAElementTreeSource(runtime: fixture.runtime)
        let container = try XCTUnwrap(source.uiaElementSnapshots().first(where: \.supportsItemContainer)?.id)
        var element: UInt64?
        for _ in 0...FramedUIAVisibilityFixture.targetIndex {
            guard case .item(let next) = source.uiaFindItem(containerID: container, afterElementID: element) else {
                return XCTFail("Expected the original public List logical item")
            }
            element = next
        }
        let elementID = try XCTUnwrap(element)
        XCTAssertEqual(source.uiaLogicalItemState(elementID: elementID), .placeholder)
        XCTAssertFalse(fixture.probe.factories.contains(FramedUIAVisibilityFixture.targetIndex))
        fixture.beginRecording()

        XCTAssertTrue(source.uiaRealizeVirtualizedItem(elementID: elementID))

        XCTAssertEqual(source.uiaLogicalItemState(elementID: elementID), .ordinary)
        let row = try fixture.targetRoot()
        try assertVisibleNoninteractiveRoot(row, in: fixture)
        try assertSettled(fixture.runtime)
        XCTAssertFalse(
            fixture.runtime.lazyListUIARejectionsForTesting.entries.contains {
                $0.site == .resolveVisibility
            })
        fixture.assertFinishedAllowance()
    }

    func testVisibleFramedRowCompletesItsOriginalRetainedRequest() async throws {
        let fixture = try FramedUIAVisibilityFixture(scenario: .visible)
        defer { fixture.host.close() }

        try fixture.withResolution { request, roots, mutation in
            let actual = try XCTUnwrap(roots)
            let row = try fixture.targetRoot()
            XCTAssertTrue(actual.contains { $0 === row })
            XCTAssertTrue(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertTrue(fixture.runtime.isAccessibilityMutationCurrent(mutation))
            try assertVisibleNoninteractiveRoot(row, in: fixture)
            try assertSettled(fixture.runtime)
            XCTAssertFalse(
                fixture.runtime.lazyListUIARejectionsForTesting.entries.contains {
                    $0.site == .resolveVisibility || $0.site == .resolveFinal
                })
        }
    }

    func testHiddenFramedRowFailsTheExistingTargetGuardBeforeScrolling() async throws {
        let fixture = try FramedUIAVisibilityFixture(scenario: .hidden)
        defer { fixture.host.close() }

        try fixture.withResolution { request, roots, mutation in
            XCTAssertNil(roots)
            let row = try fixture.targetRoot()
            XCTAssertTrue(row.isHidden)
            XCTAssertFalse(row.isHitTestVisible)
            XCTAssertTrue(row.parent === fixture.list)
            XCTAssertTrue(fixture.runtime.isAccessibilityMutationCurrent(mutation))
            XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(request.item))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertFalse(fixture.runtime.currentPrepaintState.dispatchNodes.contains { $0.node === row })
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertFalse(fixture.runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll })
            let rejection = try XCTUnwrap(fixture.runtime.lazyListUIARejectionsForTesting.entries.last)
            XCTAssertEqual(rejection.site, .resolveTarget)
            XCTAssertFalse(
                fixture.runtime.lazyListUIARejectionsForTesting.entries.contains {
                    $0.site == .resolveVisibility
                })
            // Hidden roots cannot satisfy the unchanged positive target-pass
            // guard. This control deliberately does not claim final settlement.
        }
    }

    func testFramedRowInsideTheSurfaceButClippedByItsListIsNotRevealed() async throws {
        let fixture = try FramedUIAVisibilityFixture(scenario: .clipped)
        defer { fixture.host.close() }

        try fixture.withResolution { request, roots, mutation in
            let row = try assertRejectedFinalVisibility(request, roots: roots, mutation: mutation, in: fixture)
            XCTAssertEqual(fixture.runtime.root.resolvedFrame.width, 640)
            XCTAssertEqual(fixture.scroll.resolvedFrame.width, 320)
            XCTAssertTrue(fixture.scroll.clipsToBounds)
            XCTAssertEqual(fixture.scroll.transform, .identity)
            XCTAssertEqual(row.transform, .translation(x: 350, y: 0))
            XCTAssertEqual(row.resolvedFrame.minX, 0)
            let shiftedLeft = row.resolvedFrame.minX + row.transform.applying(to: .zero).x
            XCTAssertGreaterThan(shiftedLeft, fixture.scroll.resolvedFrame.width)
            XCTAssertLessThan(shiftedLeft, fixture.runtime.root.resolvedFrame.width)
            XCTAssertFalse(fixture.runtime.currentPrepaintState.dispatchNodes.contains { $0.node === row })
        }
    }

    func testFramedRowInPrepaintButOutsideThePhysicalSurfaceIsNotRevealed() async throws {
        let fixture = try FramedUIAVisibilityFixture(scenario: .offSurface)
        defer { fixture.host.close() }

        try fixture.withResolution { request, roots, mutation in
            let row = try assertRejectedFinalVisibility(request, roots: roots, mutation: mutation, in: fixture)
            XCTAssertEqual(fixture.runtime.root.resolvedFrame.width, 320)
            XCTAssertFalse(fixture.runtime.root.clipsToBounds)
            XCTAssertEqual(fixture.runtime.root.transform, .identity)
            XCTAssertEqual(fixture.scroll.resolvedFrame.width, 320)
            XCTAssertEqual(fixture.scroll.transform, .translation(x: 640, y: 0))
            XCTAssertEqual(row.transform, .identity)
            XCTAssertGreaterThan(
                fixture.scroll.transform.applying(to: .zero).x, fixture.runtime.root.frame.size.width)
            // The scroll viewport moves with the List, so prepaint visits its
            // rows. The unchanged physical surface still clips all their area.
            XCTAssertTrue(fixture.runtime.currentPrepaintState.dispatchNodes.contains { $0.node === row })
        }
    }

    func testFramedRowWithPositiveLayoutButZeroPaintAreaIsNotRevealed() async throws {
        let fixture = try FramedUIAVisibilityFixture(scenario: .zeroPaintArea)
        defer { fixture.host.close() }

        try fixture.withResolution { request, roots, mutation in
            let row = try assertRejectedFinalVisibility(request, roots: roots, mutation: mutation, in: fixture)
            XCTAssertEqual(row.transform, .scale(x: 0, y: 1))
            XCTAssertEqual(
                row.transform.applying(to: Point(x: row.resolvedFrame.width, y: 0)),
                row.transform.applying(to: .zero))
            XCTAssertFalse(fixture.runtime.currentPrepaintState.dispatchNodes.contains { $0.node === row })
            // Width-zero frames are not fixed dimensions in the public API.
            // A singular paint transform instead keeps the actual layout and
            // target-pass premises positive while giving the target zero area.
        }
    }

    private func assertVisibleNoninteractiveRoot(
        _ row: ViewNode, in fixture: FramedUIAVisibilityFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertFalse(row.isHitTestVisible, file: file, line: line)
        XCTAssertNil(row.scrollAxis, file: file, line: line)
        XCTAssertFalse(row.isHidden, file: file, line: line)
        XCTAssertTrue(row.parent === fixture.list, file: file, line: line)
        XCTAssertGreaterThan(row.resolvedFrame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(row.resolvedFrame.height, 0, file: file, line: line)
        XCTAssertEqual(row.lastLayoutVisitPassID, fixture.runtime.layoutPassID, file: file, line: line)
        let button = try XCTUnwrap(
            fixture.host.find(FramedUIAVisibilityFixture.actionIdentifier), file: file, line: line)
        XCTAssertTrue(button.parent === row, file: file, line: line)
        XCTAssertTrue(button.isHitTestVisible, file: file, line: line)
        XCTAssertTrue(
            fixture.runtime.currentPrepaintState.dispatchNodes.contains { $0.node === row }, file: file, line: line)
        XCTAssertFalse(
            fixture.runtime.currentPrepaintState.interactions.contains { $0.node === row }, file: file, line: line)
        XCTAssertTrue(
            fixture.runtime.currentPrepaintState.interactions.contains { $0.node === button }, file: file, line: line)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0, file: file, line: line)
        let top = fixture.list.resolvedFrame.minY + row.resolvedFrame.minY - fixture.scroll.resolvedScrollOffset
        XCTAssertLessThan(top, fixture.scroll.resolvedFrame.height, file: file, line: line)
        XCTAssertGreaterThan(top + row.resolvedFrame.height, 0, file: file, line: line)
    }

    private func assertRejectedFinalVisibility(
        _ request: RetainedLazyListUIARequest, roots: [ViewNode]?, mutation: RetainedAccessibilityMutation,
        in fixture: FramedUIAVisibilityFixture, file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        XCTAssertNil(roots, file: file, line: line)
        let row = try fixture.targetRoot()
        XCTAssertFalse(row.isHidden, file: file, line: line)
        XCTAssertFalse(row.isHitTestVisible, file: file, line: line)
        XCTAssertNil(row.scrollAxis, file: file, line: line)
        XCTAssertGreaterThan(row.resolvedFrame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(row.resolvedFrame.height, 0, file: file, line: line)
        XCTAssertEqual(row.lastLayoutVisitPassID, fixture.runtime.layoutPassID, file: file, line: line)
        XCTAssertTrue(fixture.runtime.isAccessibilityMutationCurrent(mutation), file: file, line: line)
        XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(request.item), file: file, line: line)
        XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request), file: file, line: line)
        try assertSettled(fixture.runtime, file: file, line: line)
        let actual = try XCTUnwrap(
            fixture.runtime.realizedLazyListAccessibilityNodes(for: request.item), file: file, line: line)
        XCTAssertTrue(actual.contains { $0 === row }, file: file, line: line)
        XCTAssertFalse(
            fixture.runtime.currentPrepaintState.interactions.contains { $0.node === row }, file: file, line: line)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0, file: file, line: line)
        XCTAssertEqual(
            fixture.runtime.lazyListUIAPhasesForTesting.filter { $0.kind == .ownedScroll }.count, 1,
            file: file, line: line)
        let rejection = try XCTUnwrap(
            fixture.runtime.lazyListUIARejectionsForTesting.entries.last, file: file, line: line)
        XCTAssertEqual(rejection.site, .resolveVisibility, file: file, line: line)
        XCTAssertEqual(rejection.phase, .measured, file: file, line: line)
        XCTAssertGreaterThan(rejection.remainingRounds, 0, file: file, line: line)
        XCTAssertGreaterThan(rejection.remainingElements, 0, file: file, line: line)
        XCTAssertEqual(rejection.pass, fixture.runtime.layoutPassID, file: file, line: line)
        XCTAssertEqual(rejection.unmutatedGeometry, rejection.geometry, file: file, line: line)
        XCTAssertFalse(
            fixture.runtime.lazyListUIARejectionsForTesting.entries.contains {
                $0.site == .resolveTarget || $0.site == .resolveFinal || $0.site == .queryResult
            }, file: file, line: line)
        return row
    }

    private func assertSettled(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            return XCTFail("Expected the original completed query's settlement before cleanup", file: file, line: line)
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
        XCTAssertFalse(runtime.hasActiveRetainedBuild, file: file, line: line)
    }
}

private enum FramedUIAVisibilityScenario: Equatable { case visible, hidden, clipped, offSurface, zeroPaintArea }

@MainActor
private final class FramedUIAVisibilityFixture {
    static let targetIndex = 30
    static let rowIdentifier = "framed-uia-row-30"
    static let actionIdentifier = "framed-uia-action-30"
    let probe: FramedUIAVisibilityProbe
    let host: MountedLazyListTestHost
    let list: ViewNode
    let scroll: ViewNode
    let witness: RetainedLazyListAccessibilityItem

    var runtime: RetainedViewRuntime { host.runtime }

    init(scenario: FramedUIAVisibilityScenario) throws {
        let probe = FramedUIAVisibilityProbe(scenario: scenario)
        self.probe = probe
        let host: MountedLazyListTestHost
        if scenario == .clipped {
            host = MountedLazyListTestHost(size: Size(width: 640, height: 80)) {
                HStack(spacing: 0) {
                    List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain)
                        .frame(width: 320, height: 80)
                    Color.clear.frame(width: 320, height: 80)
                }
                .frame(width: 640, height: 80)
            }
        } else {
            host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
                List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain)
                    .offset(x: scenario == .offSurface ? 640 : 0)
            }
        }
        self.host = host
        let runtime = host.runtime
        do {
            XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: 16))
            XCTAssertNotNil(host.layout())
            let list = try host.list()
            let scroll = try host.scrollContainer()
            var native: RetainedLazyListAccessibilityItem?
            for _ in 0...Self.targetIndex {
                native = try XCTUnwrap(runtime.lazyListAccessibilityItem(in: list, after: native))
            }
            let witness = try XCTUnwrap(native)
            self.list = list
            self.scroll = scroll
            self.witness = witness
            XCTAssertEqual(scroll.resolvedFrame.width, 320)
            XCTAssertEqual(scroll.resolvedFrame.height, 80)
            XCTAssertEqual(scroll.scrollOffset, 0)
            XCTAssertFalse(runtime.root.clipsToBounds)
            XCTAssertFalse(probe.factories.contains(Self.targetIndex))
            XCTAssertNil(host.find(Self.rowIdentifier))
            XCTAssertTrue(runtime.isLazyListAccessibilityItemCurrent(witness))
        } catch {
            host.close()
            throw error
        }
    }

    func beginRecording() {
        runtime.recordsLazyListUIAPhasesForTesting = true
        runtime.lazyListUIARejectionsForTesting.isEnabled = true
    }

    func targetRoot() throws -> ViewNode {
        let row = try XCTUnwrap(host.find(Self.rowIdentifier))
        XCTAssertTrue(row.parent === list)
        XCTAssertTrue(list.children.contains { $0 === row })
        return row
    }

    func withResolution(
        _ inspect: (RetainedLazyListUIARequest, [ViewNode]?, RetainedAccessibilityMutation) throws -> Void
    ) throws {
        beginRecording()
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        try runtime.withLazyListResolutionBudget {
            let request = try XCTUnwrap(
                runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
            defer { runtime.finishLazyListUIARequest(request) }
            XCTAssertTrue(runtime.isLazyListAccessibilityItemCurrent(request.item))
            XCTAssertFalse(probe.factories.contains(Self.targetIndex))
            let roots = runtime.resolveLazyListUIARequest(request)
            try inspect(request, roots, mutation)
        }
        assertFinishedAllowance()
    }

    func assertFinishedAllowance(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(runtime.lastLazyListConsumedRounds, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedRounds, 16, file: file, line: line)
        XCTAssertGreaterThan(runtime.lastLazyListConsumedElements, 0, file: file, line: line)
        XCTAssertLessThan(runtime.lastLazyListConsumedElements, 128, file: file, line: line)
        XCTAssertTrue(probe.factories.contains(Self.targetIndex), file: file, line: line)
        XCTAssertTrue(probe.activations.isEmpty, file: file, line: line)
        XCTAssertFalse(runtime.hasActiveRetainedBuild, file: file, line: line)
        XCTAssertFalse(runtime.lazyListUIARejectionsForTesting.didDropEntries, file: file, line: line)
    }
}

@MainActor
private final class FramedUIAVisibilityProbe {
    let scenario: FramedUIAVisibilityScenario
    let rows = Array(0..<64)
    var factories: [Int] = []
    var activations: [Int] = []

    init(scenario: FramedUIAVisibilityScenario) { self.scenario = scenario }

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        let row = Button("Row \(id)") { [weak self] in self?.activations.append(id) }
            .accessibilityIdentifier("framed-uia-action-\(id)")
            .frame(height: 24)
            .accessibilityIdentifier("framed-uia-row-\(id)")
        guard id == FramedUIAVisibilityFixture.targetIndex else { return [AnyView(row)] }
        switch scenario {
        case .visible, .offSurface:
            return [AnyView(row)]
        case .hidden:
            return [AnyView(row.hidden())]
        case .clipped:
            return [AnyView(row.offset(x: 350))]
        case .zeroPaintArea:
            return [AnyView(row.scaleEffect(x: 0, y: 1))]
        }
    }
}
